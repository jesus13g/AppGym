from sqlalchemy import Column, Integer, String, ForeignKey, Float, DateTime
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()


class Rutina(Base):
    __tablename__ = 'rutina'
    id = Column(Integer, primary_key=True)
    nombre = Column(String, nullable=False, unique=True)  # No permitir nombres duplicados
    color = Column(String, nullable=True)  # Color con el que se pinta en el calendario

    # Relación con Entrenamiento y Ejercicio
    entrenamientos = relationship("Entrenamiento", cascade="all, delete", back_populates="rutina")
    ejercicios = relationship("Ejercicio", cascade="all, delete", back_populates="rutina")


class Entrenamiento(Base):
    __tablename__ = 'entrenamiento'
    id = Column(Integer, primary_key=True)
    id_rutina = Column(Integer, ForeignKey('rutina.id', ondelete='CASCADE'), nullable=False)  # Clave foránea a Rutina
    fecha = Column(DateTime, nullable=False)

    # Relación con Serie
    series = relationship("Serie", cascade="all, delete", back_populates="entrenamiento")
    rutina = relationship("Rutina", back_populates="entrenamientos")


class EjercicioCatalogo(Base):
    """Ejercicio del catálogo, cargado desde app/data/ejercicios.es.json.

    Es solo lectura: se siembra al arrancar y nunca se modifica desde la app.
    """
    __tablename__ = 'ejercicio_catalogo'
    id = Column(String, primary_key=True)              # "0001"
    nombre = Column(String, nullable=False)            # en inglés, tal cual viene del dataset
    body_part = Column(String, index=True)
    equipment = Column(String, index=True)
    target = Column(String, index=True)
    muscle_group = Column(String)
    secondary_muscles = Column(String)                 # JSON: lista de músculos
    instrucciones = Column(String)                     # JSON: lista de pasos en español
    image = Column(String)                             # ruta relativa dentro del dataset
    gif = Column(String)                               # ruta relativa dentro del dataset
    busqueda = Column(String, index=True)              # nombre + traducciones, sin acentos


class Ejercicio(Base):
    """Ejercicio dentro de una rutina.

    Si `id_catalogo` apunta a un `EjercicioCatalogo`, hereda imagen, músculos e
    instrucciones de él. Si es NULL, es un ejercicio personalizado del usuario y
    solo tiene `nombre` y `descripcion`.
    """
    __tablename__ = 'ejercicio'
    id = Column(Integer, primary_key=True)
    id_rutina = Column(Integer, ForeignKey('rutina.id', ondelete='CASCADE'), nullable=False)  # Clave foránea a Rutina
    id_catalogo = Column(String, ForeignKey('ejercicio_catalogo.id'), nullable=True)
    nombre = Column(String, nullable=False)
    descripcion = Column(String, nullable=True)

    # Relación con Serie
    series = relationship("Serie", cascade="all, delete", back_populates="ejercicio")
    rutina = relationship("Rutina", back_populates="ejercicios")
    catalogo = relationship("EjercicioCatalogo")


class Serie(Base):
    __tablename__ = 'serie'
    id = Column(Integer, primary_key=True)
    id_entrenamiento = Column(Integer, ForeignKey('entrenamiento.id', ondelete='CASCADE'), nullable=False)  # Clave foránea a Entrenamiento
    id_ejercicio = Column(Integer, ForeignKey('ejercicio.id', ondelete='CASCADE'), nullable=False)  # Clave foránea a Ejercicio
    n_serie = Column(Integer, nullable=False)
    repeticiones = Column(Integer, nullable=False)
    peso = Column(Float, nullable=False)

    entrenamiento = relationship("Entrenamiento", back_populates="series")
    ejercicio = relationship("Ejercicio", back_populates="series")
