from datetime import datetime

from pydantic import BaseModel, Field


class TimestampedModel(BaseModel):
    """base model mixin with automatic created_at and updated_at timestamps"""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
