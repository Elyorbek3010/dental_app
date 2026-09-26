"""add_check_in_fields_to_queue_tickets

Revision ID: a525e43212f5
Revises: d81111b30535
Create Date: 2026-09-26 22:03:07.815648

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a525e43212f5'
down_revision: Union[str, Sequence[str], None] = 'd81111b30535'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


check_in_method_enum = sa.Enum("QR", "RECEPTION", "WALK_IN", name="checkinmethod")


def upgrade() -> None:
    """Upgrade schema."""
    # 1. Create enum type in database (PostgreSQL)
    check_in_method_enum.create(op.get_bind(), checkfirst=True)

    # 2. Add checked_in_at and check_in_method columns (both nullable)
    op.add_column(
        "queue_tickets",
        sa.Column("checked_in_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "queue_tickets",
        sa.Column("check_in_method", check_in_method_enum, nullable=True),
    )

    # 3. Backfill existing WALK_IN tickets only
    op.execute(
        """
        UPDATE queue_tickets
        SET checked_in_at = created_at,
            check_in_method = 'WALK_IN'
        WHERE source = 'WALK_IN'
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    # 1. Drop check_in_method and checked_in_at columns
    op.drop_column("queue_tickets", "check_in_method")
    op.drop_column("queue_tickets", "checked_in_at")

    # 2. Drop checkinmethod enum type
    check_in_method_enum.drop(op.get_bind(), checkfirst=True)
