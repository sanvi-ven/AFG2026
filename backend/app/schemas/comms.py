from pydantic import BaseModel, EmailStr


class EmailSendRequest(BaseModel):
    """request to send a single transactional email"""
    to: EmailStr
    subject: str
    html_body: str


class SmsSendRequest(BaseModel):
    """request to send a single sms message"""
    to: str
    body: str


class SendResult(BaseModel):
    """generic delivery confirmation"""
    sent: bool
