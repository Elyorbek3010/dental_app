"""add_multilingual_names_to_specializations

Revision ID: a7a1b70f1101
Revises: 8f57d6891122
Create Date: 2026-09-28 01:52:34.792736

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a7a1b70f1101'
down_revision: Union[str, Sequence[str], None] = '8f57d6891122'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema to support multilingual specialization names."""
    # 1. Add new multilingual columns (nullable initially for migration)
    op.add_column('specializations', sa.Column('name_uz', sa.String(length=100), nullable=True))
    op.add_column('specializations', sa.Column('name_ru', sa.String(length=100), nullable=True))
    op.add_column('specializations', sa.Column('name_en', sa.String(length=100), nullable=True))

    # 2. Preserve existing data with proper natural translations where known, falling back to existing name
    op.execute("""
        UPDATE specializations
        SET
            name_uz = CASE
                WHEN name = 'General Dentistry' THEN 'Umumiy stomatologiya'
                WHEN name = 'Test General Dentistry' THEN 'Test umumiy stomatologiya'
                WHEN name = 'Orthodontics' OR name = 'Ortodontiya' THEN 'Ortodontiya'
                WHEN name = 'Pediatric Dentistry' THEN 'Bolalar stomatologiyasi'
                WHEN name = 'Surgical Dentistry' THEN 'Jarrohlik stomatologiyasi'
                WHEN name = 'Implantology' THEN 'Implantologiya'
                ELSE COALESCE(name, 'Umumiy stomatologiya')
            END,
            name_ru = CASE
                WHEN name = 'General Dentistry' THEN 'Общая стоматология'
                WHEN name = 'Test General Dentistry' THEN 'Тестовая общая стоматология'
                WHEN name = 'Orthodontics' OR name = 'Ortodontiya' THEN 'Ортодонтия'
                WHEN name = 'Pediatric Dentistry' THEN 'Детская стоматология'
                WHEN name = 'Surgical Dentistry' THEN 'Хирургическая стоматология'
                WHEN name = 'Implantology' THEN 'Имплантология'
                ELSE name
            END,
            name_en = CASE
                WHEN name = 'General Dentistry' THEN 'General Dentistry'
                WHEN name = 'Test General Dentistry' THEN 'Test General Dentistry'
                WHEN name = 'Orthodontics' OR name = 'Ortodontiya' THEN 'Orthodontics'
                WHEN name = 'Pediatric Dentistry' THEN 'Pediatric Dentistry'
                WHEN name = 'Surgical Dentistry' THEN 'Surgical Dentistry'
                WHEN name = 'Implantology' THEN 'Implantology'
                ELSE name
            END
    """)

    # 3. Enforce not null constraint on the primary language (Uzbek)
    op.alter_column('specializations', 'name_uz', nullable=False)

    # 4. Safely drop the old single-language column
    op.drop_column('specializations', 'name')


def downgrade() -> None:
    """Downgrade schema back to single name column."""
    op.add_column('specializations', sa.Column('name', sa.String(length=100), nullable=True))
    op.execute("UPDATE specializations SET name = COALESCE(name_uz, name_en, name_ru, 'General Dentistry')")
    op.alter_column('specializations', 'name', nullable=False)
    op.drop_column('specializations', 'name_en')
    op.drop_column('specializations', 'name_ru')
    op.drop_column('specializations', 'name_uz')
