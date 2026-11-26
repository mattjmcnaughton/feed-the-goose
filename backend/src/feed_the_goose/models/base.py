"""The declarative base and the column types the models share (TDD §5.2)."""

from datetime import datetime
from fractions import Fraction
from typing import Any

from sqlalchemy import DateTime, MetaData, Text, TypeDecorator
from sqlalchemy.orm import DeclarativeBase

# Constraint names are fixed so that migrations can refer to them.
NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    type_annotation_map = {datetime: DateTime(timezone=True), str: Text()}


class ExactFraction(TypeDecorator[Fraction]):
    """A `Fraction` stored exactly as text, such as `100/3`.

    Leads are exact (TDD §5.3), and a short day's lead carries into the next day, so a
    decimal column would round it.
    """

    impl = Text
    cache_ok = True

    def process_bind_param(self, value: Fraction | None, dialect: Any) -> str | None:
        return None if value is None else str(Fraction(value))

    def process_result_value(self, value: str | None, dialect: Any) -> Fraction | None:
        return None if value is None else Fraction(value)
