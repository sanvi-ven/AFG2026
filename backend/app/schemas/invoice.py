from datetime import date

from pydantic import BaseModel, Field

from app.models.enums import InvoiceStatus
from app.schemas.common import TimestampedModel


class InvoiceItem(BaseModel):
    """invoice line item with description, quantity, and unit price"""
    description: str
    quantity: int = Field(ge=1)
    unit_price: float = Field(ge=0)


class InvoiceBase(BaseModel):
    """base invoice schema with business, client, and due date"""
    business_id: str
    client_id: str
    due_date: date


class InvoiceCreate(InvoiceBase):
    """create invoice payload with line items and optional tax"""
    items: list[InvoiceItem]
    tax: float = Field(default=0, ge=0)


class InvoiceUpdateStatus(BaseModel):
    """update invoice status payload"""
    status: InvoiceStatus


class InvoiceRead(InvoiceBase, TimestampedModel):
    """complete invoice response with calculated totals and status"""
    id: str
    items: list[InvoiceItem]
    subtotal: float
    tax: float
    total: float
    status: InvoiceStatus
