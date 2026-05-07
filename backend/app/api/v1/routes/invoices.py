from fastapi import APIRouter, Depends, Query
from typing import Optional

from app.api.deps.auth import get_current_user, require_owner
from app.schemas.invoice import InvoiceCreate, InvoiceRead, InvoiceUpdateStatus
from app.schemas.user import UserRead
from app.services.invoices_service import InvoicesService

router = APIRouter()
"""invoice management routes for status tracking"""
service = InvoicesService()


@router.get("", response_model=list[InvoiceRead])
# list invoices filtered by client id
def list_invoices(
    client_id: Optional[str] = Query(default=None),
    _: UserRead = Depends(get_current_user),
) -> list[InvoiceRead]:
    return service.list_invoices(client_id=client_id)


@router.post("", response_model=InvoiceRead)
# create a new invoice
def create_invoice(payload: InvoiceCreate, _: UserRead = Depends(require_owner)) -> InvoiceRead:
    return service.create_invoice(payload)


@router.patch("/{invoice_id}/status", response_model=InvoiceRead)
# update invoice status
def update_invoice_status(
    invoice_id: str,
    payload: InvoiceUpdateStatus,
    _: UserRead = Depends(require_owner),
) -> InvoiceRead:
    return service.update_invoice_status(invoice_id, payload)
