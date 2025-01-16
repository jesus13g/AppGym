from sqlalchemy import create_engine, Column, Integer, String, ForeignKey, Float, DateTime
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

class Rutina(Base):
    __tablename__ = 'rutina'
    id = Column(Integer, primary_key=True)
    nombre = Column(String, nullable=False, unique=True)  # No permitir nombres duplicados

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


class Ejercicio(Base):
    __tablename__ = 'ejercicio'
    id = Column(Integer, primary_key=True)
    id_rutina = Column(Integer, ForeignKey('rutina.id', ondelete='CASCADE'), nullable=False)  # Clave foránea a Rutina
    nombre = Column(String, nullable=False)
    descripcion = Column(String, nullable=False)

    # Relación con Serie
    series = relationship("Serie", cascade="all, delete", back_populates="ejercicio")
    rutina = relationship("Rutina", back_populates="ejercicios")


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
