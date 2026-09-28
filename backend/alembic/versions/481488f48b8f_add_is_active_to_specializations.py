"""add_is_active_to_specializations

Revision ID: 481488f48b8f
Revises: a7a1b70f1101
Create Date: 2026-09-29 01:21:06.201119

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '481488f48b8f'
down_revision: Union[str, Sequence[str], None] = 'a7a1b70f1101'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'specializations',
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False)
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('specializations', 'is_active')
