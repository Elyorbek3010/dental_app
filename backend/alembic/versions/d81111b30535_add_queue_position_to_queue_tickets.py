"""add_queue_position_to_queue_tickets

Revision ID: d81111b30535
Revises: 40c6b2287e34
Create Date: 2026-09-23 00:29:14.640737

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd81111b30535'
down_revision: Union[str, Sequence[str], None] = '40c6b2287e34'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # 1. Add queue_position initially nullable
    op.add_column(
        "queue_tickets",
        sa.Column("queue_position", sa.Integer(), nullable=True),
    )

    # 2. Backfill existing tickets so queue_position = ticket_number
    op.execute(
        "UPDATE queue_tickets SET queue_position = ticket_number WHERE queue_position IS NULL"
    )

    # 3. Change queue_position to NOT NULL
    op.alter_column(
        "queue_tickets",
        "queue_position",
        nullable=False,
        existing_type=sa.Integer(),
    )

    # 4. Create the unique constraint (queue_id, queue_position)
    op.create_unique_constraint(
        "uq_queue_ticket_position",
        "queue_tickets",
        ["queue_id", "queue_position"],
    )


def downgrade() -> None:
    """Downgrade schema."""
    # 1. Drop unique constraint
    op.drop_constraint(
        "uq_queue_ticket_position",
        "queue_tickets",
        type_="unique",
    )

    # 2. Drop column
    op.drop_column("queue_tickets", "queue_position")

