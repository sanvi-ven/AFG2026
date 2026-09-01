from enum import Enum


class UserRole(str, Enum):
    """application user role types"""
    OWNER = "owner"
    CLIENT = "client"
    EMPLOYEE = "employee"
