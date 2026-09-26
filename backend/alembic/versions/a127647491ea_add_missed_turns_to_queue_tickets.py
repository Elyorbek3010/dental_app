"""add_missed_turns_to_queue_tickets

Revision ID: a127647491ea
Revises: a525e43212f5
Create Date: 2026-09-26 23:18:08.494542

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a127647491ea'
down_revision: Union[str, Sequence[str], None] = 'a525e43212f5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("queue_tickets") as batch_op:
        # 1. Add missed_turns column with server default 0 and NOT NULL
        batch_op.add_column(
            sa.Column(
                "missed_turns",
                sa.Integer(),
                server_default=sa.text("0"),
                nullable=False,
            )
        )

        # 2. Add check constraint to ensure missed_turns is non-negative
        batch_op.create_check_constraint(
            "ck_queue_ticket_missed_turns_non_negative",
            "missed_turns >= 0",
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("queue_tickets") as batch_op:
        # 1. Drop check constraint
        batch_op.drop_constraint(
            "ck_queue_ticket_missed_turns_non_negative",
            type_="check",
        )

        # 2. Drop column
        batch_op.drop_column("missed_turns")
