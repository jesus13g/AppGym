from sqlalchemy import create_engine, func, text
from sqlalchemy.orm import sessionmaker, joinedload
from sqlalchemy.exc import SQLAlchemyError
from app.utils.modelo import Base, Rutina, Entrenamiento, Ejercicio, EjercicioCatalogo, Serie
from app.utils.i18n import normalizar
from app.utils import almacenamiento
import threading

# Paleta de colores iOS que se reparte entre las rutinas para el calendario.
COLORES_RUTINA = [
    "#0A84FF",  # azul
    "#30D158",  # verde
    "#FF9F0A",  # naranja
    "#FF375F",  # rosa
    "#BF5AF2",  # morado
    "#40C8E0",  # turquesa
    "#5E5CE6",  # índigo
    "#FFD60A",  # amarillo
]


class ConexionBD:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self, db_url=None):
        """
        Inicializa la conexión a la base de datos.
        :param db_url: URL de la base de datos; por defecto, un SQLite en el
                       almacenamiento de la app (ver app/utils/almacenamiento.py)
        """
        if getattr(self, "initialized", False):
            return
        self.db_url = db_url or almacenamiento.ruta_base_datos()
        self.engine = create_engine(self.db_url, connect_args={"check_same_thread": False})
        self.Session = sessionmaker(bind=self.engine)
        self.initialized = True

    def delete_all(self):
        """
        Elimina todas las tablas existentes en la base de datos.
        """
        try:
            Base.metadata.drop_all(self.engine)
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al eliminar tablas: {e}")
        except Exception as e:
            print(f"Error al eliminar: {e}")

    def create_tablas(self):
        """
        Crea las tablas que falten y migra las que ya existan de versiones antiguas.
        """
        try:
            Base.metadata.create_all(self.engine)
            self._migrar_columnas()
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al crear tablas: {e}")
        except Exception as e:
            print(f"Error al crear tablas: {e}")

    def _migrar_columnas(self):
        """Añade las columnas nuevas a bases de datos creadas con versiones anteriores.

        `create_all` crea tablas nuevas pero nunca modifica las existentes, así que
        una DataBase.db antigua se quedaría sin `ejercicio.id_catalogo` ni
        `rutina.color`. Este bloque es idempotente: consulta el esquema real y solo
        añade lo que falte.
        """
        nuevas = {
            "ejercicio": [("id_catalogo", "VARCHAR")],
            "rutina": [("color", "VARCHAR")],
        }
        with self.engine.begin() as conexion:
            for tabla, columnas in nuevas.items():
                existentes = {
                    fila[1] for fila in conexion.execute(text(f"PRAGMA table_info({tabla})"))
                }
                if not existentes:
                    continue  # la tabla no existe todavía; create_all ya la habrá hecho bien
                for nombre, tipo in columnas:
                    if nombre not in existentes:
                        conexion.execute(text(f"ALTER TABLE {tabla} ADD COLUMN {nombre} {tipo}"))
                        print(f"Migración: añadida {tabla}.{nombre}")

            # Las rutinas que vienen de una BD antigua no tienen color asignado.
            sin_color = conexion.execute(
                text("SELECT id FROM rutina WHERE color IS NULL ORDER BY id")
            ).fetchall()
            for posicion, (id_rutina,) in enumerate(sin_color):
                conexion.execute(
                    text("UPDATE rutina SET color = :color WHERE id = :id"),
                    {"color": COLORES_RUTINA[posicion % len(COLORES_RUTINA)], "id": id_rutina},
                )

    def get_sesion(self):
        """
        Devuelve una nueva sesión de la base de datos.
        """
        return self.Session()

    def close_sesion(self, sesion):
        """
        Cierra una sesión de la base de datos.
        :param sesion: Sesión a cerrar
        """
        sesion.close()

    ##################################################################################################
    # Rutinas
    ##################################################################################################

    def insert_newRutina(self, nombre):
        """
        Inserta una nueva rutina y le asigna un color de la paleta.
        :param nombre: Nombre de la rutina
        :return: ID de la rutina creada, o None si ya existía o falló
        """
        sesion = self.get_sesion()
        try:
            if sesion.query(Rutina).filter_by(nombre=nombre).first():
                return None
            usados = sesion.query(func.count(Rutina.id)).scalar() or 0
            rutina = Rutina(nombre=nombre, color=COLORES_RUTINA[usados % len(COLORES_RUTINA)])
            sesion.add(rutina)
            sesion.commit()
            return rutina.id
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy al insertar rutina: {e}")
        except Exception as e:
            sesion.rollback()
            print(f"Error al insertar rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def delete_rutina(self, id_rutina):
        """
        Elimina una rutina junto con sus entrenamientos y ejercicios.
        :param id_rutina: ID de la rutina a eliminar
        """
        sesion = self.get_sesion()
        try:
            rutina = sesion.query(Rutina).filter_by(id=id_rutina).first()
            if rutina:
                sesion.delete(rutina)  # Se eliminan también entrenamientos y ejercicios debido al cascade
                sesion.commit()
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy al eliminar rutina: {e}")
        except Exception as e:
            sesion.rollback()
            print(f"Error al eliminar rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)

    def rename_rutina(self, id_rutina, nombre):
        """Renombra una rutina. Devuelve True si se aplicó el cambio."""
        sesion = self.get_sesion()
        try:
            existente = sesion.query(Rutina).filter(
                Rutina.nombre == nombre, Rutina.id != id_rutina
            ).first()
            if existente:
                return False
            rutina = sesion.query(Rutina).filter_by(id=id_rutina).first()
            if not rutina:
                return False
            rutina.nombre = nombre
            sesion.commit()
            return True
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy al renombrar rutina: {e}")
        except Exception as e:
            sesion.rollback()
            print(f"Error al renombrar rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return False

    def selectId_rutina(self, nombre_rutina):
        """
        Devuelve el ID de una rutina por su nombre, o None si no existe.
        :param nombre_rutina: Nombre de la rutina
        """
        sesion = self.get_sesion()
        try:
            rutina = sesion.query(Rutina).filter_by(nombre=nombre_rutina).first()
            return rutina.id if rutina else None
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener rutina: {e}")
        except Exception as e:
            print(f"Error al obtener rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def select_NombreRutina(self, id_rutina):
        """
        Devuelve una rutina por su ID, o None si no existe.
        :param id_rutina: ID de la rutina
        """
        sesion = self.get_sesion()
        try:
            return sesion.query(Rutina).filter_by(id=id_rutina).first()
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener rutina: {e}")
        except Exception as e:
            print(f"Error al obtener rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def selectAll_rutinas(self):
        """
        Devuelve todas las rutinas de la base de datos.
        """
        sesion = self.get_sesion()
        rutinas = []
        try:
            rutinas = sesion.query(Rutina).order_by(Rutina.id).all()
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener rutinas: {e}")
        except Exception as e:
            print(f"Error al obtener rutinas: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return rutinas

    def resumen_rutinas(self):
        """Devuelve, por rutina, su nombre, color, nº de ejercicios y última fecha entrenada.

        Se resuelve en tres consultas agregadas en vez de una por rutina, porque la
        lista de rutinas es la primera pantalla y se repinta constantemente.
        :return: lista de dicts con id, nombre, color, n_ejercicios y ultima_fecha
        """
        sesion = self.get_sesion()
        resumen = []
        try:
            conteos = dict(
                sesion.query(Ejercicio.id_rutina, func.count(Ejercicio.id))
                .group_by(Ejercicio.id_rutina)
                .all()
            )
            ultimas = dict(
                sesion.query(Entrenamiento.id_rutina, func.max(Entrenamiento.fecha))
                .group_by(Entrenamiento.id_rutina)
                .all()
            )
            for rutina in sesion.query(Rutina).order_by(Rutina.id).all():
                resumen.append({
                    "id": rutina.id,
                    "nombre": rutina.nombre,
                    "color": rutina.color,
                    "n_ejercicios": conteos.get(rutina.id, 0),
                    "ultima_fecha": ultimas.get(rutina.id),
                })
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener el resumen de rutinas: {e}")
        except Exception as e:
            print(f"Error al obtener el resumen de rutinas: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return resumen

    ##################################################################################################
    # Ejercicios de una rutina
    ##################################################################################################

    def insert_newEjercicio(self, id_rutina, nombre, descripcion=None, id_catalogo=None):
        """
        Añade un ejercicio a una rutina.

        El duplicado se comprueba **dentro de la rutina**: dos rutinas distintas sí
        pueden compartir el mismo ejercicio del catálogo.
        :return: True si se insertó, False si ya estaba o falló
        """
        sesion = self.get_sesion()
        try:
            consulta = sesion.query(Ejercicio).filter(Ejercicio.id_rutina == id_rutina)
            if id_catalogo is not None:
                consulta = consulta.filter(Ejercicio.id_catalogo == id_catalogo)
            else:
                consulta = consulta.filter(
                    Ejercicio.id_catalogo.is_(None), Ejercicio.nombre == nombre
                )
            if consulta.first():
                return False

            sesion.add(Ejercicio(
                id_rutina=id_rutina,
                id_catalogo=id_catalogo,
                nombre=nombre,
                descripcion=descripcion,
            ))
            sesion.commit()
            return True
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy al insertar ejercicio: {e}")
        except Exception as e:
            sesion.rollback()
            print(f"Error al insertar ejercicio: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return False

    def delete_ejercicio(self, id_rutina, id_ejercicio):
        """Quita un ejercicio de una rutina, con sus series registradas."""
        sesion = self.get_sesion()
        try:
            ejercicio = sesion.query(Ejercicio).filter(
                Ejercicio.id_rutina == id_rutina,
                Ejercicio.id == id_ejercicio,
            ).first()
            if ejercicio:
                sesion.delete(ejercicio)  # borra sus series por el cascade
                sesion.commit()
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy al eliminar un ejercicio: {e}")
        except Exception as e:
            sesion.rollback()
            print(f"Error al eliminar un ejercicio: {e}")
        finally:
            self.close_sesion(sesion=sesion)

    def select_ejercicio(self, id_ejercicio):
        """
        Devuelve un ejercicio por su ID, con su ficha de catálogo ya cargada.
        :param id_ejercicio: ID del ejercicio
        """
        sesion = self.get_sesion()
        try:
            return (
                sesion.query(Ejercicio)
                .options(joinedload(Ejercicio.catalogo))
                .filter_by(id=id_ejercicio)
                .first()
            )
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener ejercicio: {e}")
        except Exception as e:
            print(f"Error al obtener ejercicio: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def selectAll_ejerciciosRutina(self, id_rutina):
        """
        Devuelve todos los ejercicios de una rutina, con su ficha de catálogo.
        :param id_rutina: ID de la rutina
        """
        sesion = self.get_sesion()
        ejercicios = []
        try:
            ejercicios = (
                sesion.query(Ejercicio)
                .options(joinedload(Ejercicio.catalogo))
                .filter_by(id_rutina=id_rutina)
                .order_by(Ejercicio.id)
                .all()
            )
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener ejercicios: {e}")
        except Exception as e:
            print(f"Error al obtener ejercicios: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return ejercicios

    def count_ejercicios_rutina(self, id_rutina):
        """Cuenta los ejercicios de una rutina."""
        sesion = self.get_sesion()
        try:
            return sesion.query(func.count(Ejercicio.id)).filter_by(id_rutina=id_rutina).scalar() or 0
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al contar ejercicios: {e}")
        except Exception as e:
            print(f"Error al contar ejercicios: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return 0

    def ids_catalogo_en_rutina(self, id_rutina):
        """Devuelve el set de ids de catálogo ya añadidos a una rutina.

        Lo usa el buscador para marcar con un check lo que ya está en la rutina.
        """
        sesion = self.get_sesion()
        try:
            filas = (
                sesion.query(Ejercicio.id_catalogo)
                .filter(Ejercicio.id_rutina == id_rutina, Ejercicio.id_catalogo.isnot(None))
                .all()
            )
            return {fila[0] for fila in filas}
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener ejercicios de la rutina: {e}")
        except Exception as e:
            print(f"Error al obtener ejercicios de la rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return set()

    ##################################################################################################
    # Catálogo
    ##################################################################################################

    def count_catalogo(self):
        """Número de ejercicios sembrados en el catálogo."""
        sesion = self.get_sesion()
        try:
            return sesion.query(func.count(EjercicioCatalogo.id)).scalar() or 0
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al contar el catálogo: {e}")
        except Exception as e:
            print(f"Error al contar el catálogo: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return 0

    def buscar_catalogo(self, texto=None, body_part=None, equipment=None, limit=40, offset=0):
        """
        Busca en el catálogo. Todos los filtros son opcionales y se combinan con AND.
        :param texto: se busca en la columna `busqueda` (nombre + traducciones, sin acentos)
        :param body_part: valor original en inglés, p.ej. "chest"
        :param equipment: valor original en inglés, p.ej. "dumbbell"
        """
        sesion = self.get_sesion()
        try:
            consulta = sesion.query(EjercicioCatalogo)
            if texto:
                for palabra in normalizar(texto).split():
                    consulta = consulta.filter(EjercicioCatalogo.busqueda.like(f"%{palabra}%"))
            if body_part:
                consulta = consulta.filter(EjercicioCatalogo.body_part == body_part)
            if equipment:
                consulta = consulta.filter(EjercicioCatalogo.equipment == equipment)
            return consulta.order_by(EjercicioCatalogo.nombre).limit(limit).offset(offset).all()
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al buscar en el catálogo: {e}")
        except Exception as e:
            print(f"Error al buscar en el catálogo: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return []

    def get_catalogo(self, id_catalogo):
        """Devuelve una ficha del catálogo por su id ("0001")."""
        sesion = self.get_sesion()
        try:
            return sesion.query(EjercicioCatalogo).filter_by(id=id_catalogo).first()
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener del catálogo: {e}")
        except Exception as e:
            print(f"Error al obtener del catálogo: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def equipamientos_disponibles(self):
        """Lista ordenada de equipamientos presentes en el catálogo."""
        sesion = self.get_sesion()
        try:
            filas = sesion.query(EjercicioCatalogo.equipment).distinct().all()
            return sorted(fila[0] for fila in filas if fila[0])
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener equipamientos: {e}")
        except Exception as e:
            print(f"Error al obtener equipamientos: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return []

    ##################################################################################################
    # Entrenamientos y series
    ##################################################################################################

    def insert_newEntrenamiento(self, id_rutina, fecha, series: dict):
        """
        Inserta un nuevo entrenamiento en la base de datos.
        :param fecha: Fecha del entrenamiento
        :param id_rutina: ID de la rutina a la que pertenece
        :param series: dict id_ejercicio -> {"series", "repeticiones", "peso"}
        :return: True si se guardó
        """
        if not series:
            return False

        sesion = self.get_sesion()
        try:
            entrenamiento = Entrenamiento(id_rutina=id_rutina, fecha=fecha)
            sesion.add(entrenamiento)
            sesion.flush()

            for id_ejercicio, valores in series.items():
                sesion.add(Serie(
                    id_entrenamiento=entrenamiento.id,
                    id_ejercicio=id_ejercicio,
                    n_serie=valores["series"],
                    repeticiones=valores["repeticiones"],
                    peso=valores["peso"],
                ))
            sesion.commit()
            return True
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy al insertar entrenamiento: {e}")
        except Exception as e:
            sesion.rollback()
            print(f"Error al insertar entrenamiento: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return False

    def select_entrenamiento(self, id_entrenamiento):
        """
        Devuelve un entrenamiento por su ID.
        :param id_entrenamiento: ID del entrenamiento
        """
        sesion = self.get_sesion()
        try:
            return sesion.query(Entrenamiento).filter_by(id=id_entrenamiento).first()
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener entrenamiento: {e}")
        except Exception as e:
            print(f"Error al obtener entrenamiento: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def select_entrenamientoSeries(self, fecha):
        """
        Devuelve un entrenamiento por su fecha y las series asociadas.
        :param fecha: Fecha del entrenamiento
        :return: (entrenamiento, series) o (None, None)
        """
        sesion = self.get_sesion()
        try:
            entrenamiento = sesion.query(Entrenamiento).filter_by(fecha=fecha).first()
            if not entrenamiento:
                return None, None
            return entrenamiento, list(entrenamiento.series)
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener entrenamiento: {e}")
        except Exception as e:
            print(f"Error al obtener entrenamiento: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None, None

    def select_series_from_entrenamientos(self, id_rutina, id_ejercicio):
        """
        Devuelve las series de un ejercicio en una rutina, ordenadas por fecha.
        :param id_rutina: ID de la rutina
        :param id_ejercicio: ID del ejercicio
        """
        sesion = self.get_sesion()
        series = []
        try:
            series = (
                sesion.query(Serie)
                .join(Entrenamiento, Serie.id_entrenamiento == Entrenamiento.id)
                .filter(
                    Entrenamiento.id_rutina == id_rutina,
                    Serie.id_ejercicio == id_ejercicio,
                )
                .order_by(Entrenamiento.fecha)
                .all()
            )
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener series: {e}")
        except Exception as e:
            print(f"Error al obtener series: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return series

    def series_con_fecha(self, id_rutina, id_ejercicio):
        """Igual que select_series_from_entrenamientos pero devolviendo también la fecha.

        Evita que la pantalla de progreso tenga que recorrer las series accediendo a
        `serie.entrenamiento.fecha` con la sesión ya cerrada.
        :return: lista de dicts con fecha, series, repeticiones y peso
        """
        sesion = self.get_sesion()
        datos = []
        try:
            filas = (
                sesion.query(Entrenamiento.fecha, Serie.n_serie, Serie.repeticiones, Serie.peso)
                .join(Serie, Serie.id_entrenamiento == Entrenamiento.id)
                .filter(
                    Entrenamiento.id_rutina == id_rutina,
                    Serie.id_ejercicio == id_ejercicio,
                )
                .order_by(Entrenamiento.fecha)
                .all()
            )
            datos = [
                {"fecha": f, "series": n, "repeticiones": r, "peso": p}
                for f, n, r, p in filas
            ]
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener series: {e}")
        except Exception as e:
            print(f"Error al obtener series: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return datos

    def ultima_serie_ejercicio(self, id_ejercicio):
        """Devuelve los valores del último registro de un ejercicio, para precargarlos.

        :return: dict con series/repeticiones/peso, o None si nunca se ha entrenado
        """
        sesion = self.get_sesion()
        try:
            fila = (
                sesion.query(Serie)
                .join(Entrenamiento, Serie.id_entrenamiento == Entrenamiento.id)
                .filter(Serie.id_ejercicio == id_ejercicio)
                .order_by(Entrenamiento.fecha.desc(), Serie.id.desc())
                .first()
            )
            if not fila:
                return None
            return {
                "series": fila.n_serie,
                "repeticiones": fila.repeticiones,
                "peso": fila.peso,
            }
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener la última serie: {e}")
        except Exception as e:
            print(f"Error al obtener la última serie: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def ultimo_entrenamiento_rutina(self, id_rutina):
        """Fecha del último entrenamiento de una rutina, o None."""
        sesion = self.get_sesion()
        try:
            return (
                sesion.query(func.max(Entrenamiento.fecha))
                .filter(Entrenamiento.id_rutina == id_rutina)
                .scalar()
            )
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener el último entrenamiento: {e}")
        except Exception as e:
            print(f"Error al obtener el último entrenamiento: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return None

    def count_entrenamientos_rutina(self, id_rutina):
        """Número de entrenamientos registrados de una rutina."""
        sesion = self.get_sesion()
        try:
            return sesion.query(func.count(Entrenamiento.id)).filter_by(id_rutina=id_rutina).scalar() or 0
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al contar entrenamientos: {e}")
        except Exception as e:
            print(f"Error al contar entrenamientos: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return 0

    def selectAll_entrenamientos(self):
        """
        Devuelve un dict fecha (date) -> id_rutina con todos los entrenamientos.

        Si un día tiene varios entrenamientos se queda el más reciente, que es el
        que colorea la celda del calendario.
        """
        sesion = self.get_sesion()
        fechas_entrenamientos = {}
        try:
            entrenamientos = sesion.query(Entrenamiento).order_by(Entrenamiento.fecha).all()
            for entrenamiento in entrenamientos:
                fechas_entrenamientos[entrenamiento.fecha.date()] = entrenamiento.id_rutina
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener entrenamientos: {e}")
        except Exception as e:
            print(f"Error al obtener entrenamientos: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return fechas_entrenamientos

    def colores_rutinas(self):
        """Devuelve un dict id_rutina -> (nombre, color) para pintar la leyenda."""
        sesion = self.get_sesion()
        try:
            return {
                r.id: (r.nombre, r.color or COLORES_RUTINA[(r.id - 1) % len(COLORES_RUTINA)])
                for r in sesion.query(Rutina).all()
            }
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy al obtener colores: {e}")
        except Exception as e:
            print(f"Error al obtener colores: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return {}
