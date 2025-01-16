from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import SQLAlchemyError, IntegrityError
from app.utils.modelo import Base, Rutina, Entrenamiento, Ejercicio, Serie
from datetime import datetime
import threading

class ConexionBD:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            with cls._lock:
                cls._instance = super().__new__(cls, *args, **kwargs)
        return cls._instance


    def __init__(self, db_url="sqlite:///mi_base_de_datos.db"):
        """
        Inicializa la conexión a la base de datos.
        :param db_url: URL de la base de datos (por defecto usa SQLite)
        """
        if not hasattr(self, "initialized"):
            self.db_url = db_url
            self.engine = create_engine(self.db_url, connect_args={"check_same_thread": False})
            self.Session = sessionmaker(bind=self.engine)

    def delete_all(self):
        """
        Elimina todas las tablas existentes en la base de datos.
        """
        try:
            Base.metadata.drop_all(self.engine)
            print("Todas las tablas han sido eliminadas.")
        except Exception as e:
            print(f"Error al eliminar: {e}")

    def create_tablas(self):
        """
        Crea las tablas en la base de datos si no existen.
        """
        try:
            Base.metadata.create_all(self.engine)
            print("Las tablas se han creado correctamente.")
        except Exception as e:
            print(f"Error al crear tablas: {e}")

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


    def insert_newRutina(self, nombre):
        """
        Inserta una nueva rutina en la base de datos.
        :param nombre: Nombre de la rutina
        """
        sesion = self.get_sesion()
        try:
            rutina_existente = sesion.query(Rutina).filter_by(nombre=nombre).first()
            if not rutina_existente:
                rutina = Rutina(nombre=nombre)
                sesion.add(rutina)
                sesion.commit()

        except SQLAlchemyError as e:
            print(f"Error SQLAlchemy: {e}")
        except Exception as e:
            print(f"Error al insertar rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)


    def delete_rutina(self, id_rutina):
        """
        Elimina una rutina de la base de datos junto con sus entrenamientos y ejercicios.
        :param id_rutina: ID de la rutina a eliminar
        """
        sesion = self.get_sesion()
        try:
            rutina = sesion.query(Rutina).filter_by(id=id_rutina).first()
            if rutina:
                sesion.delete(rutina)  # Se eliminan también entrenamientos y ejercicios debido al cascade
                sesion.commit()
                
        except Exception as e:
            sesion.rollback()
            print(f"Error al eliminar rutina: {e}")
        finally:
            self.close_sesion(sesion=sesion)




    def delete_ejercicio(self, id_rutina, id_ejercicio):
        sesion = self.get_sesion()

        try:
            sesion.query(Ejercicio).filter(
                Ejercicio.id_rutina == id_rutina,
                Ejercicio.id == id_ejercicio
            ).delete(synchronize_session='fetch')
            sesion.commit()

        except Exception as e:
            print(f"Error al eliminar un ejercicio: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
    
    
    def insert_newEjercicio(self, id_rutina, nombre, descripcion):
        """
        Inserta un nuevo ejercicio en la base de datos.
        :param nombre: Nombre del ejercicio
        :param descripcion: Descripción del ejercicio
        :param id_rutina: ID de la rutina a la que pertenece
        """
        sesion = self.get_sesion()
        try:
            ejercicio_existente = sesion.query(Ejercicio).filter_by(nombre=nombre).first()
            if ejercicio_existente:
                pass
            else:
                ejercicio = Ejercicio(id_rutina=id_rutina, nombre=nombre, descripcion=descripcion)
                sesion.add(ejercicio)
                sesion.commit()
                
        except Exception as e:
            print(f"Error al insertar ejercicio: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)

    
    def insert_newEntrenamiento(self, id_rutina, fecha, series:dict):
        """
        Inserta un nuevo entrenamiento en la base de datos.
        :param fecha: Fecha del entrenamiento
        :param id_rutina: ID de la rutina a la que pertenece
        :param series: dict de dict como valor con los datos de una serie id_ejercicio: {peso, repeticiones, etc.}}
        """
        sesion = self.get_sesion()
        
        try:
            entrenamiento = Entrenamiento(id_rutina=id_rutina, fecha=fecha)
            sesion.add(entrenamiento)

            sesion.flush()
            
            id_entrenamiento = entrenamiento.id
            for id_ejercicio, valores in series.items():
                serie = Serie(id_entrenamiento=id_entrenamiento,
                                id_ejercicio=id_ejercicio, 
                                n_serie=valores["series"],
                                repeticiones=valores["repeticiones"],
                                peso=valores["peso"], 
                            )
                sesion.add(serie)
            sesion.commit()
            
        except Exception as e:
            sesion.rollback()
            print(f"Error al insertar entrenamiento: {e}")
        except SQLAlchemyError as e:
            sesion.rollback()
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)


    def select_entrenamiento(self, id_entrenamiento):
        """
        Devuelve un entrenamiento por su ID.
        :param id_entrenamiento: ID del entrenamiento
        """
        sesion = self.get_sesion()
        try:
            entrenamiento = sesion.query(Entrenamiento).filter_by(id=id_entrenamiento).first()
            if not entrenamiento:
                return None
        except Exception as e:
            print(f"Error al obtener entrenamiento: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return entrenamiento


    def select_entrenamientoSeries(self, fecha):
        """
        Devuelve un entrenamiento por su fecha y las series asociadas.
        :param fecha: Fecha del entrenamiento
        :return: Entrenamiento y series asociadas
        """
        sesion = self.get_sesion()
        try:
            entrenamiento = sesion.query(Entrenamiento).filter_by(fecha=fecha).first()
            if not entrenamiento:
                return None, None

            return entrenamiento, entrenamiento.series
        except Exception as e:
            print(f"Error al obtener entrenamiento: {e}")
        finally:
            self.close_sesion(sesion=sesion)



    def select_series_from_entrenamientos(self, id_rutina, id_ejercicio):
        """
        Devuelve las series de un ejercicio en una rutina.
        :param id_rutina: ID de la rutina
        :param id_ejercicio: ID del ejercicio
        """
        sesion = self.get_sesion()
        series = [] 
        try:
            # Realizamos una consulta join entre las tablas Entrenamiento y Serie.
            series = sesion.query(Serie).join(Entrenamiento).filter(
                Entrenamiento.id_rutina == id_rutina,
                Serie.id_ejercicio == id_ejercicio,
                Serie.id_entrenamiento == Entrenamiento.id
            ).all()

        except Exception as e:
            print(f"Error al obtener series: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return series


    def selectId_rutina(self, nombre_rutina):
        """
        Devuelve el ID de una rutina por su nombre.
        :param nombre_rutina: Nombre de la rutina
        """
        sesion = self.get_sesion()
        try:
            rutina = sesion.query(Rutina).filter_by(nombre=nombre_rutina).first()
            if not rutina:
                return None
        except Exception as e:
            print(f"Error al obtener rutina: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return rutina.id


    def select_NombreRutina(self, id_rutina):
        """
        Devuelve una rutina por su ID.
        :param id_rutina: ID de la rutina
        """
        sesion = self.get_sesion()
        try:
            rutina = sesion.query(Rutina).filter_by(id=id_rutina).first()
            if not rutina:
                return None
        except Exception as e:
            print(f"Error al obtener rutina: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return rutina


    def select_ejercicio(self, id_ejercicio):
        """
        Devuelve un ejercicio por su ID.
        :param id_ejercicio: ID del ejercicio
        """
        sesion = self.get_sesion()
        try:
            ejercicio = sesion.query(Ejercicio).filter_by(id=id_ejercicio).first()
            if not ejercicio:
                print(f"No se ha encontrado el ejercicio con ID {id_ejercicio}")
                return None
        except Exception as e:
            print(f"Error al obtener ejercicio: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return ejercicio


    def selectAll_rutinas(self):
        """
        Devuelve todas las rutinas de la base de datos.
        """
        sesion = self.get_sesion()
        rutinas = None
        try:
            rutinas = sesion.query(Rutina).all()
        except Exception as e:
            print(f"Error al obtener rutinas: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return rutinas


    def selectAll_ejerciciosRutina(self, id_rutina):
        """
        Devuelve todos los ejercicios de una rutina.
        :param id_rutina: ID de la rutina
        """
        sesion = self.get_sesion()
        ejercicios = None
        try:
            ejercicios = sesion.query(Ejercicio).filter_by(id_rutina=id_rutina).all()
        except Exception as e:
            print(f"Error al obtener ejercicios: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return ejercicios
    
    
    def selectAll_entrenamientos(self):
        """
        Devuelve todos los entrenamientos de la base de datos.
        """
        sesion = self.get_sesion()
        entrenamientos = None
        try:
            entrenamientos = sesion.query(Entrenamiento).all()
            fechas_entrenamientos = {}
            for entrenamiento in entrenamientos:
                fechas_entrenamientos[entrenamiento.fecha.date()] = entrenamiento.id_rutina
        except Exception as e:
            print(f"Error al obtener entrenamientos: {e}")
        except SQLAlchemyError as e:
            print(f"Error de SQLAlchemy: {e}")
        finally:
            self.close_sesion(sesion=sesion)
        return fechas_entrenamientos

