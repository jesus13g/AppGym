-- ═══════════════════════════════════════════════════════════════════════════════
-- AppGym — esquema de sincronización (fase 8c)
--
-- Se pega tal cual en el editor SQL de Supabase. Es idempotente: volver a
-- ejecutarlo sobre un proyecto ya montado no destruye nada.
--
-- El montaje completo de un proyecto —incluida la plantilla de correo, que es
-- el paso que más se olvida— está en `docs/sincronizacion.md`.
--
--
-- ── Qué es esto ───────────────────────────────────────────────────────────────
--
-- Un buzón con reloj. El servidor **no sabe qué es una rutina**: guarda lo que
-- `FilaRemota` transporta (tabla, clave, sello y datos) y lo único que decide es
-- el sello, que es justamente lo que un cliente con la hora mal puesta no puede
-- falsear.
--
-- Que la carga útil vaya en `jsonb` y no en seis tablas espejo es una desviación
-- consciente de lo que preveía K2, y el motivo está razonado en
-- `docs/especificaciones-2.md`. En corto: la costura de la fase 8b ya es
-- genérica por fila, `serie` no tiene identidad propia —viaja dentro de su
-- entrenamiento—, el motor está construido para tolerar huérfanos (la
-- cuarentena) y por tanto una clave foránea aquí rechazaría paquetes que el
-- cliente sabe colocar, y sobre todo: el APK se instala a mano desde una
-- release, así que conviven versiones arbitrarias. Con tablas espejo, añadir una
-- columna en el móvil exigiría desplegar una migración aquí **antes**; con
-- `jsonb` el servidor no se entera.
--
--
-- ── Dónde vive ────────────────────────────────────────────────────────────────
--
-- Las tablas van en el esquema `appgym`, que **no** debe estar en «Exposed
-- schemas» del panel: así la única superficie REST son las cinco funciones de
-- `public`. Aun así llevan RLS, porque la defensa no puede depender de un ajuste
-- del panel que alguien cambie dentro de un año.
-- ═══════════════════════════════════════════════════════════════════════════════

create schema if not exists appgym;


-- ═══════════════════════════════════════════════════════════════════════════════
-- Las tablas
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Las filas ─────────────────────────────────────────────────────────────────
create table if not exists appgym.filas (
  usuario     uuid   not null references auth.users (id) on delete cascade,
  tabla       text   not null,
  clave       text   not null,

  -- El sello que puso este servidor. Estrictamente creciente por usuario.
  actualizado bigint not null,

  -- `NULL` de SQL es una lápida, igual que `FilaRemota.datos == null`.
  --
  -- Ojo con la distinción: `'null'::jsonb` es un valor JSON y **no** es una
  -- lápida. Por eso al escribir se filtra con `jsonb_typeof(...) = 'object'`, y
  -- no comparando contra `'null'::jsonb`.
  datos       jsonb,

  primary key (usuario, tabla, clave)
);

-- El índice del delta: `appgym_bajar` es exactamente esta consulta.
create index if not exists filas_delta on appgym.filas (usuario, actualizado);


-- ── El reloj ──────────────────────────────────────────────────────────────────
--
-- Una fila por usuario. **Se siembra con la hora de época en milisegundos** y a
-- partir de ahí solo sube +1 por cada fila aceptada. Las dos mitades importan, y
-- cada una tapa un fallo distinto:
--
--   · Sembrarlo alto. `identidad.selloLocal()` sella en milisegundos de época, y
--     `MotorSincro.pendientes(cursor)` sube todo lo que tenga `actualizado >
--     cursorSubida`. Un servidor que empezara en 0 dejaría el `cursorSubida` del
--     móvil en un número de dos cifras, por debajo de todos sus sellos locales,
--     y **cada pasada resubiría el histórico entero, para siempre**. El
--     transporte falso de los tests arranca en 1.000.000 «a propósito»; aquí eso
--     deja de ser una precaución y es un requisito.
--
--   · No volver a mirar la hora de pared después. `appgym_bajar` devuelve este
--     sello tal cual y `appgym_subir` devuelve el mismo valor como
--     `cursorPrevio`. El motor compara `cursorPrevio` con su `cursorBajada` para
--     saber si lo que hay entre medias lo escribió él mismo; si `subir`
--     adelantara el reloj a la hora actual, esa comparación no casaría nunca y
--     cada móvil se descargaría su propio eco en cada pasada.
--
-- Que el sello se vaya alejando de la hora de pared no importa a nadie: el
-- cliente llama a `sembrarSello(respuesta.cursor)` y `AppBD` lo re-siembra al
-- abrir con el mayor sello de la base. Es un contador, no una fecha, y en
-- ningún sitio se enseña.
create table if not exists appgym.relojes (
  usuario uuid   primary key references auth.users (id) on delete cascade,
  sello   bigint not null
);


-- ═══════════════════════════════════════════════════════════════════════════════
-- Aislamiento: cada usuario ve lo suyo y nada más
-- ═══════════════════════════════════════════════════════════════════════════════

alter table appgym.filas   enable row level security;
alter table appgym.relojes enable row level security;

drop policy if exists filas_propias on appgym.filas;
create policy filas_propias on appgym.filas
  for all to authenticated
  using      (usuario = (select auth.uid()))
  with check (usuario = (select auth.uid()));

drop policy if exists relojes_propios on appgym.relojes;
create policy relojes_propios on appgym.relojes
  for all to authenticated
  using      (usuario = (select auth.uid()))
  with check (usuario = (select auth.uid()));

-- `anon` no recibe nada: sin sesión no hay nada que ver.
grant usage on schema appgym to authenticated;
grant select, insert, update, delete on appgym.filas   to authenticated;
grant select, insert, update         on appgym.relojes to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════
-- Las funciones
--
-- Todas `security invoker` salvo la de borrar la cuenta, para que quien decide
-- siga siendo la RLS y no la función. Y todas con `set search_path = ''` y los
-- nombres cualificados: sin eso, un `search_path` del llamante podría resolver
-- `filas` o `uid()` contra otra cosa suya.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── subir ─────────────────────────────────────────────────────────────────────
--
-- Bloquea el reloj del usuario, reparte sellos estrictamente crecientes en el
-- orden en que llegaron las filas, escribe y devuelve `{sellos, cursor,
-- cursorPrevio}`. Todo en una transacción: dos móviles subiendo a la vez se
-- ordenan en el `for update`, que es lo que hace que «gana quien llega el
-- último» signifique algo.
--
-- **El `actualizado` del cliente no se envía y no se mira.** Que sea
-- estructuralmente imposible que el reloj del móvil influya es mejor que
-- ignorarlo por convenio: es el octavo escenario de K10, el del móvil con la
-- hora adelantada dos años.
--
-- Entra `[{tabla, clave, datos}]`. El cliente lo parte en lotes (200 filas por
-- omisión), así que este cuerpo no crece sin límite aunque el primer enlace
-- traiga dos años de histórico.
create or replace function public.appgym_subir(p_filas jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_previo  bigint;
  v_cursor  bigint;
  v_sellos  jsonb;
begin
  if v_usuario is null then
    raise exception 'sin sesión' using errcode = '42501';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    raise exception 'p_filas tiene que ser un array' using errcode = 'P0001';
  end if;

  -- La primera subida de una cuenta siembra su reloj con la hora de época.
  insert into appgym.relojes (usuario, sello)
  values (v_usuario, (extract(epoch from clock_timestamp()) * 1000)::bigint)
  on conflict (usuario) do nothing;

  select sello into v_previo
    from appgym.relojes
   where usuario = v_usuario
     for update;

  with entrada as (
    select f, orden
      from jsonb_array_elements(p_filas) with ordinality as e(f, orden)
  ),
  -- Deduplicado defensivo: `on conflict do update` no puede tocar dos veces la
  -- misma fila en una sentencia («cannot affect row a second time»). Se queda la
  -- última enviada, que es la fresca.
  limpia as (
    select distinct on (f ->> 'tabla', f ->> 'clave')
           f ->> 'tabla' as tabla,
           f ->> 'clave' as clave,
           case when jsonb_typeof(f -> 'datos') = 'object'
                then f -> 'datos' end as datos,
           orden
      from entrada
     where f ->> 'tabla' is not null
       and f ->> 'clave' is not null
     order by f ->> 'tabla', f ->> 'clave', orden desc
  ),
  sellada as (
    select tabla, clave, datos,
           v_previo + row_number() over (order by orden) as actualizado
      from limpia
  ),
  escrita as (
    insert into appgym.filas as d (usuario, tabla, clave, actualizado, datos)
    select v_usuario, tabla, clave, actualizado, datos from sellada
    on conflict (usuario, tabla, clave) do update
       set actualizado = excluded.actualizado,
           datos       = excluded.datos
    returning d.tabla, d.clave, d.actualizado
  )
  select coalesce(jsonb_object_agg(tabla || '/' || clave, actualizado),
                  '{}'::jsonb),
         coalesce(max(actualizado), v_previo)
    into v_sellos, v_cursor
    from escrita;

  update appgym.relojes set sello = v_cursor where usuario = v_usuario;

  return jsonb_build_object(
    'sellos',       v_sellos,
    'cursor',       v_cursor,
    'cursorPrevio', v_previo
  );
end;
$$;


-- ── bajar ─────────────────────────────────────────────────────────────────────
--
-- **El reloj se lee ANTES que las filas, y las filas se acotan por arriba con
-- él.** Al revés —filas primero, reloj después— una subida de otro dispositivo
-- que se colara en medio adelantaría el cursor por encima de filas que este
-- cliente no ha recibido, y esas filas no se bajarían jamás. Es la única forma
-- de perder datos en todo el fichero, así que el orden de estas dos consultas no
-- es estético.
--
-- Devuelve el cursor también cuando la lista viene vacía: `Paquete.cursor` tiene
-- que avanzar igual.
create or replace function public.appgym_bajar(p_cursor bigint default 0)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_cursor  bigint;
  v_filas   jsonb;
begin
  if v_usuario is null then
    raise exception 'sin sesión' using errcode = '42501';
  end if;

  select sello into v_cursor
    from appgym.relojes
   where usuario = v_usuario;
  v_cursor := coalesce(v_cursor, 0);

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'tabla',       tabla,
               'clave',       clave,
               'actualizado', actualizado,
               -- `NULL` de SQL sale como `null` de JSON, que es la lápida.
               'datos',       datos
             )
             order by actualizado
           ),
           '[]'::jsonb)
    into v_filas
    from appgym.filas
   where usuario = v_usuario
     and actualizado >  coalesce(p_cursor, 0)
     and actualizado <= v_cursor;

  return jsonb_build_object('cursor', v_cursor, 'filas', v_filas);
end;
$$;


-- ── resumen ───────────────────────────────────────────────────────────────────
--
-- Las dos cifras del primer enlace (K7): «En la cuenta: 2 rutinas, 180
-- sesiones». Sin números, la pregunta de qué lado manda no se puede responder.
--
-- Las lápidas no cuentan: `datos is not null`.
create or replace function public.appgym_resumen()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'rutinas',  count(*) filter (where tabla = 'rutinas'        and datos is not null),
    'sesiones', count(*) filter (where tabla = 'entrenamientos' and datos is not null)
  )
  from appgym.filas
  where usuario = auth.uid();
$$;


-- ── vaciar ────────────────────────────────────────────────────────────────────
--
-- Borra los datos y **conserva la cuenta y el reloj**. Lo usa «este dispositivo
-- manda» del primer enlace.
--
-- Que el reloj no se reinicie es deliberado: repartiría otra vez sellos ya
-- usados, y un dispositivo cuyo cursor estuviera por encima no volvería a ver
-- nunca lo que se subiera después.
--
-- **Limitación conocida.** Es un borrado duro, sin lápidas. Un tercer
-- dispositivo ya enlazado no se entera —no hay nada que bajar— y conserva sus
-- datos locales; tampoco los resucita, porque no están pendientes. Solo
-- volverían a la cuenta si ese dispositivo edita alguno. La alternativa
-- —enterrarlo todo en vez de borrarlo— propagaría el borrado a los datos locales
-- de ese tercer móvil, que es peor y contradice «desactivar la sincronización
-- deja los datos locales intactos». Con dos dispositivos, que es el caso de uso
-- de K, no se da.
create or replace function public.appgym_vaciar()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'sin sesión' using errcode = '42501';
  end if;
  delete from appgym.filas where usuario = auth.uid();
end;
$$;


-- ── borrar la cuenta ──────────────────────────────────────────────────────────
--
-- La única `security definer` del fichero, y hace falta que lo sea: borrar de
-- `auth.users` es cosa del `service_role`, y esa clave **no puede viajar dentro
-- del APK** bajo ningún concepto.
--
-- Por qué es seguro que lo sea:
--
--   · **No tiene argumentos.** A quien se borra es a `auth.uid()`, que sale de
--     un JWT que GoTrue ya verificó. No hay forma de nombrar a otro usuario.
--   · `set search_path = ''` y todo cualificado: el llamante no puede colar un
--     `users` propio por delante de `auth.users`.
--   · `revoke ... from public, anon` más abajo: con la clave anónima no se puede
--     ni invocar, y aunque se invocara, `auth.uid()` sería null y levanta.
--   · Los datos se van con el usuario por el `on delete cascade` de las dos
--     tablas, en la misma transacción. No hay estado que quede a medias.
--
-- Los datos **locales** no se tocan: eso lo decide la app, y la nube es una
-- copia, no el original.
create or replace function public.appgym_borrar_cuenta()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
begin
  if v_usuario is null then
    raise exception 'sin sesión' using errcode = '42501';
  end if;
  delete from auth.users where id = v_usuario;
end;
$$;


-- ── Permisos de las funciones ─────────────────────────────────────────────────
--
-- Postgres concede `execute` a `public` por defecto en cuanto se crea una
-- función. Hay que quitarlo a mano, o cualquiera con la clave anónima podría
-- llamarlas.
revoke execute on function public.appgym_subir(jsonb)    from public, anon;
revoke execute on function public.appgym_bajar(bigint)   from public, anon;
revoke execute on function public.appgym_resumen()       from public, anon;
revoke execute on function public.appgym_vaciar()        from public, anon;
revoke execute on function public.appgym_borrar_cuenta() from public, anon;

grant execute on function public.appgym_subir(jsonb)     to authenticated;
grant execute on function public.appgym_bajar(bigint)    to authenticated;
grant execute on function public.appgym_resumen()        to authenticated;
grant execute on function public.appgym_vaciar()         to authenticated;
grant execute on function public.appgym_borrar_cuenta()  to authenticated;
