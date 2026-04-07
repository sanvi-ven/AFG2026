from datetime import date

from pydantic import BaseModel, Field

from app.models.enums import InvoiceStatus
from app.schemas.common import TimestampedModel


class InvoiceItem(BaseModel):
    description: str
    quantity: int = Field(ge=1)
    unit_price: float = Field(ge=0)


class InvoiceBase(BaseModel):
    business_id: str
    client_id: str
    due_date: date


class InvoiceCreate(InvoiceBase):
    items: list[InvoiceItem]
    tax: float = Field(default=0, ge=0)


class InvoiceUpdateStatus(BaseModel):
    status: InvoiceStatus


class InvoiceRead(InvoiceBase, TimestampedModel):
    id: str
    items: list[InvoiceItem]
    subtotal: float
    tax: float
    total: float
    status: InvoiceStatus
