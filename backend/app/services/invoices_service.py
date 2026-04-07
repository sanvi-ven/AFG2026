from typing import Optional

from app.models.enums import InvoiceStatus
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.invoice import InvoiceCreate, InvoiceRead, InvoiceUpdateStatus


class InvoicesService:
    def __init__(self) -> None:
        self.repository = FirestoreRepository("invoices")

    def create_invoice(self, payload: InvoiceCreate) -> InvoiceRead:
        subtotal = sum(item.quantity * item.unit_price for item in payload.items)
        total = subtotal + payload.tax
        record = payload.model_dump()
        record.update({"subtotal": subtotal, "total": total, "status": InvoiceStatus.DRAFT})
        saved = self.repository.create(record)
        return InvoiceRead.model_validate(saved)

    def list_invoices(self, client_id: Optional[str] = None) -> list[InvoiceRead]:
        rows = self.repository.list("client_id", client_id) if client_id else self.repository.list()
        return [InvoiceRead.model_validate(row) for row in rows]

    def update_invoice_status(self, invoice_id: str, payload: InvoiceUpdateStatus) -> InvoiceRead:
        updated = self.repository.update(invoice_id, payload.model_dump())
        return InvoiceRead.model_validate(updated)
