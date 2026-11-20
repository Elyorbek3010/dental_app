"""add_doctor_shift_lifecycle_and_history

Revision ID: b3c4d5e6f7a8
Revises: a2b3c4d5e6f7
Create Date: 2026-11-21 02:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b3c4d5e6f7a8'
down_revision: Union[str, Sequence[str], None] = 'a2b3c4d5e6f7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add clinic timezone, doctor shift lifecycle columns/index, and ticket completion timestamp."""
    op.add_column(
        'clinics',
        sa.Column(
            'timezone',
            sa.String(length=64),
            server_default=sa.text("'Asia/Tashkent'"),
            nullable=False,
        ),
    )

    # Add shift lifecycle columns cleanly; leave legacy started_at/ended_at/completed_at NULL
    # so historical timestamps are never fabricated.
    op.add_column(
        'queues',
        sa.Column(
            'shift_status',
            sa.String(length=16),
            server_default=sa.text("'OPEN'"),
            nullable=False,
        ),
    )
    op.add_column(
        'queues',
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'queues',
        sa.Column('ended_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_check_constraint(
        'ck_queue_shift_status_valid',
        'queues',
        "shift_status IN ('OPEN', 'CLOSING', 'FINISHED')",
    )

    op.add_column(
        'queue_tickets',
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        'ix_queue_tickets_completed_at',
        'queue_tickets',
        ['completed_at'],
        unique=False,
    )

    # Deterministic backfill for existing queues before switching uniqueness constraint:
    # 1. Any queue with is_active = FALSE is FINISHED.
    # 2. Past-date queues (queue_date < CURRENT_DATE) without live CALLED/SERVING/WAITING tickets
    #    are historical and finalized to FINISHED (is_active = FALSE, is_paused = FALSE).
    # 3. For safety, if a doctor still has >1 active row, keep only the newest row OPEN.
    op.execute(
        sa.text(
            """
            UPDATE queues
            SET shift_status = 'FINISHED',
                is_paused = FALSE
            WHERE is_active = FALSE
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE queues q
            SET shift_status = 'FINISHED',
                is_active = FALSE,
                is_paused = FALSE
            WHERE q.is_active = TRUE
              AND q.queue_date < CURRENT_DATE
              AND NOT EXISTS (
                  SELECT 1 FROM queue_tickets t
                  WHERE t.queue_id = q.id
                    AND t.status IN ('WAITING', 'CALLED', 'SERVING')
              )
            """
        )
    )
    op.execute(
        sa.text(
            """
            WITH ranked AS (
                SELECT id,
                       ROW_NUMBER() OVER (
                           PARTITION BY doctor_id
                           ORDER BY queue_date DESC, id DESC
                       ) AS rn
                FROM queues
                WHERE shift_status IN ('OPEN', 'CLOSING')
            )
            UPDATE queues q
            SET shift_status = 'FINISHED',
                is_active = FALSE,
                is_paused = FALSE
            FROM ranked r
            WHERE q.id = r.id
              AND r.rn > 1
            """
        )
    )

    op.drop_constraint('uq_queue_doctor_date', 'queues', type_='unique')
    op.create_index(
        'uq_queue_one_active_shift_per_doctor',
        'queues',
        ['doctor_id'],
        unique=True,
        postgresql_where=sa.text("shift_status IN ('OPEN', 'CLOSING')"),
    )
    op.create_index('ix_queues_doctor_started', 'queues', ['doctor_id', 'started_at'], unique=False)
    op.create_index('ix_queues_queue_date', 'queues', ['queue_date'], unique=False)


def downgrade() -> None:
    """Revert shift lifecycle schema changes (for isolated disposable DB tests only)."""
    op.drop_index('ix_queues_queue_date', table_name='queues')
    op.drop_index('ix_queues_doctor_started', table_name='queues')
    op.drop_index('uq_queue_one_active_shift_per_doctor', table_name='queues')

    # Keep at most one legacy row per (doctor_id, queue_date) when reverting on a disposable test DB
    op.execute(
        sa.text(
            """
            UPDATE queues
            SET is_active = CASE WHEN shift_status = 'FINISHED' THEN FALSE ELSE TRUE END
            """
        )
    )
    op.execute(
        sa.text(
            """
            WITH dupes AS (
                SELECT id,
                       ROW_NUMBER() OVER (PARTITION BY doctor_id, queue_date ORDER BY id ASC) AS rn
                FROM queues
            )
            DELETE FROM queue_tickets
            WHERE queue_id IN (SELECT id FROM dupes WHERE rn > 1)
            """
        )
    )
    op.execute(
        sa.text(
            """
            WITH dupes AS (
                SELECT id,
                       ROW_NUMBER() OVER (PARTITION BY doctor_id, queue_date ORDER BY id ASC) AS rn
                FROM queues
            )
            DELETE FROM queues
            WHERE id IN (SELECT id FROM dupes WHERE rn > 1)
            """
        )
    )
    op.create_unique_constraint('uq_queue_doctor_date', 'queues', ['doctor_id', 'queue_date'])

    op.drop_index('ix_queue_tickets_completed_at', table_name='queue_tickets')
    op.drop_column('queue_tickets', 'completed_at')

    op.drop_constraint('ck_queue_shift_status_valid', 'queues', type_='check')
    op.drop_column('queues', 'ended_at')
    op.drop_column('queues', 'started_at')
    op.drop_column('queues', 'shift_status')

    op.drop_column('clinics', 'timezone')
