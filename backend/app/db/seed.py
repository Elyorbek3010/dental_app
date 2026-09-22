from datetime import date

from sqlalchemy import select

from app.core.security import get_password_hash
from app.db.session import SessionLocal
from app.models import Clinic, Doctor, Queue, Specialization, User, UserRole


def seed_data() -> None:
    today = date.today()
    with SessionLocal() as db:
        # 1. Clinic
        clinic = db.scalar(
            select(Clinic).where(Clinic.name == "Dental Test Clinic")
        )
        if not clinic:
            clinic = Clinic(name="Dental Test Clinic")
            db.add(clinic)
            db.flush()

        # 2. Specialization
        specialization = db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == clinic.id,
                Specialization.name == "General Dentistry",
            )
        )
        if not specialization:
            specialization = Specialization(
                clinic_id=clinic.id,
                name="General Dentistry",
            )
            db.add(specialization)
            db.flush()

        # 3. Doctor
        doctor = db.scalar(
            select(Doctor).where(
                Doctor.clinic_id == clinic.id,
                Doctor.full_name == "Dr. Test Dentist",
            )
        )
        if not doctor:
            doctor = Doctor(
                clinic_id=clinic.id,
                specialization_id=specialization.id,
                full_name="Dr. Test Dentist",
                room_number="101",
                is_active=True,
            )
            db.add(doctor)
            db.flush()

        # 4. Today's Queue
        queue = db.scalar(
            select(Queue).where(
                Queue.doctor_id == doctor.id,
                Queue.queue_date == today,
            )
        )
        if not queue:
            queue = Queue(
                doctor_id=doctor.id,
                queue_date=today,
                is_paused=False,
                is_active=True,
            )
            db.add(queue)
            db.flush()

        # 5. Receptionist User
        old_receptionist_phone = "+998900000002"
        new_receptionist_phone = "+998905555555"

        receptionist = db.scalar(
            select(User).where(User.phone == new_receptionist_phone)
        )
        if not receptionist:
            receptionist = db.scalar(
                select(User).where(User.phone == old_receptionist_phone)
            )

        if receptionist:
            receptionist.full_name = "Test Receptionist"
            receptionist.phone = new_receptionist_phone
            receptionist.hashed_password = get_password_hash("12345678")
            receptionist.role = UserRole.RECEPTIONIST
            receptionist.clinic_id = clinic.id
            receptionist.is_active = True
        else:
            receptionist = User(
                full_name="Test Receptionist",
                phone=new_receptionist_phone,
                hashed_password=get_password_hash("12345678"),
                role=UserRole.RECEPTIONIST,
                clinic_id=clinic.id,
                is_active=True,
            )
            db.add(receptionist)
            db.flush()

        db.commit()
        db.refresh(clinic)
        db.refresh(specialization)
        db.refresh(doctor)
        db.refresh(queue)
        db.refresh(receptionist)

        print(f"clinic_id: {clinic.id}")
        print(f"specialization_id: {specialization.id}")
        print(f"doctor_id: {doctor.id}")
        print(f"queue_id: {queue.id}")
        print(f"receptionist_id: {receptionist.id}")
        print(f"receptionist_phone: {receptionist.phone}")
        print(f"receptionist_role: {receptionist.role.value if hasattr(receptionist.role, 'value') else receptionist.role}")
        print(f"receptionist_clinic_id: {receptionist.clinic_id}")


if __name__ == "__main__":
    seed_data()
