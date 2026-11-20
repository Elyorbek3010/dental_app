"""add_smart_call_mode_to_queues

Revision ID: a2b3c4d5e6f7
Revises: f1a2b3c4d5e6
Create Date: 2026-11-21 00:50:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a2b3c4d5e6f7'
down_revision: Union[str, Sequence[str], None] = 'f1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add server-authoritative smart_call_mode to daily doctor queues."""
    op.add_column(
        'queues',
        sa.Column(
            'smart_call_mode',
            sa.String(length=16),
            server_default=sa.text("'MANUAL'"),
            nullable=False,
        ),
    )
    op.create_check_constraint(
        'ck_queue_smart_call_mode_valid',
        'queues',
        "smart_call_mode IN ('MANUAL', 'AUTOMATIC')",
    )


def downgrade() -> None:
    """Remove smart_call_mode column and validation constraint."""
    op.drop_constraint('ck_queue_smart_call_mode_valid', 'queues', type_='check')
    op.drop_column('queues', 'smart_call_mode')
