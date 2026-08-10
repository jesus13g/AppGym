"""Las cuatro tablas: usuarios, refrescos, filas y relojes.

Revisión: 0001
Anterior: ninguna
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "usuarios",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("correo", sa.String(320), nullable=False, unique=True),
        sa.Column("contrasena_hash", sa.Text(), nullable=False),
        sa.Column(
            "creado", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("ultimo_acceso", sa.DateTime(timezone=True)),
        sa.Column("intentos_fallidos", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("bloqueado_hasta", sa.DateTime(timezone=True)),
    )

    op.create_table(
        "refrescos",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("familia", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "creado", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("caduca", sa.DateTime(timezone=True), nullable=False),
        sa.Column("usado", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("revocado", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index("refrescos_familia", "refrescos", ["usuario_id", "familia"])

    op.create_table(
        "filas",
        sa.Column(
            "usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("tabla", sa.String(64), primary_key=True),
        sa.Column("clave", sa.String(128), primary_key=True),
        sa.Column("actualizado", sa.BigInteger(), nullable=False),
        sa.Column("datos", postgresql.JSONB()),
    )
    # El índice del delta: `bajar` es exactamente esta consulta.
    op.create_index("filas_delta", "filas", ["usuario_id", "actualizado"])

    op.create_table(
        "relojes",
        sa.Column(
            "usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("sello", sa.BigInteger(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("relojes")
    op.drop_index("filas_delta", table_name="filas")
    op.drop_table("filas")
    op.drop_index("refrescos_familia", table_name="refrescos")
    op.drop_table("refrescos")
    op.drop_table("usuarios")
