from enum import Enum


class UserRole(str, Enum):
    """application user role types"""
    OWNER = "owner"
    CLIENT = "client"
    EMPLOYEE = "employee"


class AppointmentStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CANCELED = "canceled"


class InvoiceStatus(str, Enum):
    DRAFT = "draft"
    SENT = "sent"
    PAID = "paid"
    OVERDUE = "overdue"


class NotificationTarget(str, Enum):
    SINGLE = "single"
    ALL_CLIENTS = "all_clients"
