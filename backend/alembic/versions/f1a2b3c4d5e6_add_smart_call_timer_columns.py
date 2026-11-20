"""add_smart_call_timer_columns

Revision ID: f1a2b3c4d5e6
Revises: 481488f48b8f
Create Date: 2026-11-20 17:26:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f1a2b3c4d5e6'
down_revision: Union[str, Sequence[str], None] = '481488f48b8f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema with Smart Call timer configuration and deadline tracking."""
    op.add_column(
        'clinics',
        sa.Column(
            'smart_call_timeout_seconds',
            sa.Integer(),
            server_default=sa.text('120'),
            nullable=False,
        ),
    )
    op.create_check_constraint(
        'ck_clinic_smart_call_timeout_range',
        'clinics',
        'smart_call_timeout_seconds >= 15 AND smart_call_timeout_seconds <= 1800',
    )

    op.add_column(
        'queue_tickets',
        sa.Column('called_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'queue_tickets',
        sa.Column('call_deadline_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'queue_tickets',
        sa.Column('paused_remaining_seconds', sa.Integer(), nullable=True),
    )
    op.create_check_constraint(
        'ck_queue_ticket_paused_remaining_non_negative',
        'queue_tickets',
        'paused_remaining_seconds IS NULL OR paused_remaining_seconds >= 0',
    )
    op.create_index(
        'ix_queue_tickets_status_deadline',
        'queue_tickets',
        ['status', 'call_deadline_at'],
        unique=False,
    )


def downgrade() -> None:
    """Revert Smart Call timer columns and constraints."""
    op.drop_index('ix_queue_tickets_status_deadline', table_name='queue_tickets')
    op.drop_constraint('ck_queue_ticket_paused_remaining_non_negative', 'queue_tickets', type_='check')
    op.drop_column('queue_tickets', 'paused_remaining_seconds')
    op.drop_column('queue_tickets', 'call_deadline_at')
    op.drop_column('queue_tickets', 'called_at')

    op.drop_constraint('ck_clinic_smart_call_timeout_range', 'clinics', type_='check')
    op.drop_column('clinics', 'smart_call_timeout_seconds')
