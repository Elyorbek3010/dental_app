from __future__ import annotations

import csv
import io
from datetime import date, datetime, timedelta, timezone
from typing import Any, Literal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue, ShiftStatus
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.models.specialization import Specialization
from app.schemas.admin import (
    AdminDoctorPerformanceResponse,
    DoctorPerformanceItem,
    DoctorPerformanceSummary,
    DoctorShiftHistoryItem,
)
from app.services.shift_service import (
    get_clinic_local_date,
    get_clinic_zoneinfo,
    local_date_range_to_utc,
)

ReportingPeriod = Literal["today", "week", "month", "year", "custom", "all"]


def sanitize_csv_cell(value: Any) -> str:
    """
    Escape leading spreadsheet formula characters (=, +, -, @, tab, CR) to protect
    CSV exports against formula injection in Excel / Google Sheets / LibreOffice.
    """
    if value is None:
        return ""
    text_val = str(value)
    stripped = text_val.lstrip(" \t\r\n")
    if stripped and stripped[0] in ("=", "+", "-", "@"):
        return f"'{text_val}"
    if text_val and text_val[0] in ("\t", "\r"):
        return f"'{text_val}"
    return text_val


def resolve_reporting_dates(
    period: ReportingPeriod,
    local_today: date,
    date_from: date | None,
    date_to: date | None,
) -> tuple[date | None, date | None]:
    """Resolve inclusive clinic-local calendar date bounds for the selected period."""
    if period == "today":
        return local_today, local_today
    if period == "week":
        week_start = local_today - timedelta(days=local_today.weekday())
        return week_start, local_today
    if period == "month":
        month_start = local_today.replace(day=1)
        return month_start, local_today
    if period == "year":
        year_start = local_today.replace(month=1, day=1)
        return year_start, local_today
    if period == "custom":
        start = date_from or local_today
        end = date_to or start
        if end < start:
            start, end = end, start
        return start, end
    return None, None


def compute_doctor_performance_and_history(
    db: Session,
    clinic: Clinic,
    *,
    doctor_id: int | None = None,
    specialization_id: int | None = None,
    period: ReportingPeriod = "today",
    date_from: date | None = None,
    date_to: date | None = None,
    lang: str = "uz",
    now_utc: datetime | None = None,
) -> AdminDoctorPerformanceResponse:
    """
    Calculate clinic-scoped doctor performance metrics using stored PostgreSQL records.
    Calendar-day counts use recorded `QueueTicket.completed_at` converted to `clinic.timezone`.
    Legacy COMPLETED rows lacking `completed_at` are never fabricated; they are included
    in shift totals and all-time totals and surfaced in `legacy_unattributed_completed_count`.
    """
    utc_now = now_utc.astimezone(timezone.utc) if now_utc is not None else datetime.now(timezone.utc)
    tz = get_clinic_zoneinfo(clinic.timezone)
    local_today = get_clinic_local_date(clinic, now_utc=utc_now)

    today_start, today_end = local_date_range_to_utc(local_today, local_today, clinic.timezone)
    week_start_d = local_today - timedelta(days=local_today.weekday())
    week_start, week_end = local_date_range_to_utc(week_start_d, local_today, clinic.timezone)
    month_start_d = local_today.replace(day=1)
    month_start, month_end = local_date_range_to_utc(month_start_d, local_today, clinic.timezone)
    year_start_d = local_today.replace(month=1, day=1)
    year_start, year_end = local_date_range_to_utc(year_start_d, local_today, clinic.timezone)

    sel_from, sel_to = resolve_reporting_dates(period, local_today, date_from, date_to)
    if sel_from is not None and sel_to is not None:
        sel_utc_start, sel_utc_end = local_date_range_to_utc(sel_from, sel_to, clinic.timezone)
    else:
        sel_utc_start, sel_utc_end = None, None

    # Fetch matching clinic doctors and specializations
    doc_stmt = (
        select(Doctor, Specialization)
        .outerjoin(Specialization, Doctor.specialization_id == Specialization.id)
        .where(Doctor.clinic_id == clinic.id)
        .order_by(Doctor.full_name.asc())
    )
    if doctor_id is not None:
        doc_stmt = doc_stmt.where(Doctor.id == doctor_id)
    if specialization_id is not None:
        doc_stmt = doc_stmt.where(Doctor.specialization_id == specialization_id)

    doc_rows = db.execute(doc_stmt).all()
    doctor_ids = [d.id for d, _s in doc_rows]

    if not doctor_ids:
        return AdminDoctorPerformanceResponse(
            clinic_id=clinic.id,
            clinic_name=clinic.name,
            clinic_timezone=str(tz),
            period=period,
            date_from=sel_from,
            date_to=sel_to,
            generated_at=utc_now,
            summary=DoctorPerformanceSummary(
                completed_today=0,
                completed_this_week=0,
                completed_this_month=0,
                completed_this_year=0,
                completed_all_time=0,
                completed_in_selected_range=0,
                legacy_unattributed_completed_count=0,
                total_shifts=0,
                active_shifts=0,
                finished_shifts=0,
            ),
            doctors=[],
            shifts=[],
        )

    # Fetch COMPLETED tickets for calendar-date / all-time stats in one query
    completed_rows = db.execute(
        select(Queue.doctor_id, QueueTicket.id, QueueTicket.completed_at)
        .join(Queue, QueueTicket.queue_id == Queue.id)
        .where(
            Queue.doctor_id.in_(doctor_ids),
            QueueTicket.status == TicketStatus.COMPLETED,
        )
    ).all()

    doc_metrics: dict[int, dict[str, int]] = {
        did: {
            "today": 0,
            "week": 0,
            "month": 0,
            "year": 0,
            "all_time": 0,
            "selected": 0,
            "legacy_unattributed": 0,
        }
        for did in doctor_ids
    }

    for row_doc_id, _tid, comp_at in completed_rows:
        m = doc_metrics[row_doc_id]
        m["all_time"] += 1
        if comp_at is None:
            m["legacy_unattributed"] += 1
            if sel_utc_start is None:
                m["selected"] += 1
            continue
        comp_utc = comp_at if comp_at.tzinfo is not None else comp_at.replace(tzinfo=timezone.utc)
        comp_utc = comp_utc.astimezone(timezone.utc)
        if today_start <= comp_utc < today_end:
            m["today"] += 1
        if week_start <= comp_utc < week_end:
            m["week"] += 1
        if month_start <= comp_utc < month_end:
            m["month"] += 1
        if year_start <= comp_utc < year_end:
            m["year"] += 1
        if sel_utc_start is not None and sel_utc_end is not None:
            if sel_utc_start <= comp_utc < sel_utc_end:
                m["selected"] += 1
        else:
            m["selected"] += 1

    # Fetch all queues for matching doctors, compute shift durations & filter shift history cleanly
    all_queues = list(
        db.scalars(
            select(Queue)
            .where(Queue.doctor_id.in_(doctor_ids))
            .order_by(Queue.queue_date.desc(), Queue.id.desc())
        ).all()
    )

    doc_map = {d.id: (d, s) for d, s in doc_rows}
    filtered_queues: list[Queue] = []
    active_shift_label_by_doc: dict[int, str] = {}

    for q in all_queues:
        if q.shift_status in (ShiftStatus.OPEN, ShiftStatus.CLOSING):
            active_shift_label_by_doc[q.doctor_id] = (
                "PAUSED" if q.is_paused else q.shift_status.value
            )

        q_local_date = (
            q.started_at.astimezone(tz).date()
            if q.started_at is not None
            else q.queue_date
        )
        if sel_from is not None and sel_to is not None:
            # Include a shift if it started in [sel_from, sel_to], OR its queue_date is in range,
            # OR it ended in range (so overnight shifts show cleanly in both relevant views).
            in_range = (sel_from <= q_local_date <= sel_to) or (sel_from <= q.queue_date <= sel_to)
            if not in_range and q.ended_at is not None:
                q_end_local = q.ended_at.astimezone(tz).date()
                in_range = sel_from <= q_end_local <= sel_to
            if not in_range and q.shift_status in (ShiftStatus.OPEN, ShiftStatus.CLOSING):
                # Still check if it overlaps today when viewing 'today'
                if sel_from <= local_today <= sel_to and q.started_at is not None and q.started_at < sel_utc_end:
                    in_range = True
            if not in_range:
                continue
        filtered_queues.append(q)

    # Aggregate ticket counts per filtered queue cleanly in one GROUP BY query
    filtered_q_ids = [q.id for q in filtered_queues]
    counts_by_queue: dict[int, dict[TicketStatus, int]] = {qid: {} for qid in filtered_q_ids}
    if filtered_q_ids:
        grouped = db.execute(
            select(QueueTicket.queue_id, QueueTicket.status, func.count(QueueTicket.id))
            .where(QueueTicket.queue_id.in_(filtered_q_ids))
            .group_by(QueueTicket.queue_id, QueueTicket.status)
        ).all()
        for qid, st, cnt in grouped:
            counts_by_queue[qid][st] = cnt

    shifts_per_doc: dict[int, int] = {did: 0 for did in doctor_ids}
    durations_per_doc: dict[int, list[int]] = {did: [] for did in doctor_ids}
    shift_items: list[DoctorShiftHistoryItem] = []

    for q in filtered_queues:
        doc, spec = doc_map[q.doctor_id]
        st_map = counts_by_queue.get(q.id, {})
        duration_seconds: int | None = None
        if q.started_at is not None and q.ended_at is not None:
            s_utc = q.started_at if q.started_at.tzinfo else q.started_at.replace(tzinfo=timezone.utc)
            e_utc = q.ended_at if q.ended_at.tzinfo else q.ended_at.replace(tzinfo=timezone.utc)
            duration_seconds = max(0, int((e_utc - s_utc).total_seconds()))
            durations_per_doc[q.doctor_id].append(duration_seconds)

        shifts_per_doc[q.doctor_id] += 1
        total_t = sum(st_map.values())
        shift_items.append(
            DoctorShiftHistoryItem(
                queue_id=q.id,
                doctor_id=doc.id,
                doctor_name=doc.full_name,
                specialization_id=doc.specialization_id,
                specialization_name=spec.get_localized_name(lang) if spec else "-",
                room_number=doc.room_number,
                queue_date=q.queue_date,
                shift_status=q.shift_status,
                is_paused=q.is_paused,
                smart_call_mode=q.smart_call_mode,
                started_at=q.started_at,
                ended_at=q.ended_at,
                duration_seconds=duration_seconds,
                total_tickets=total_t,
                completed_count=st_map.get(TicketStatus.COMPLETED, 0),
                waiting_count=st_map.get(TicketStatus.WAITING, 0),
                called_count=st_map.get(TicketStatus.CALLED, 0),
                serving_count=st_map.get(TicketStatus.SERVING, 0),
                skipped_count=st_map.get(TicketStatus.SKIPPED, 0),
                cancelled_count=st_map.get(TicketStatus.CANCELLED, 0),
            )
        )

    doctor_items: list[DoctorPerformanceItem] = []
    for doc, spec in doc_rows:
        m = doc_metrics[doc.id]
        durs = durations_per_doc[doc.id]
        avg_mins = round((sum(durs) / len(durs)) / 60.0, 1) if durs else None
        doctor_items.append(
            DoctorPerformanceItem(
                doctor_id=doc.id,
                doctor_name=doc.full_name,
                specialization_id=doc.specialization_id,
                specialization_name=spec.get_localized_name(lang) if spec else "-",
                room_number=doc.room_number,
                is_active=doc.is_active,
                current_shift_status=active_shift_label_by_doc.get(doc.id, "NONE"),
                completed_today=m["today"],
                completed_this_week=m["week"],
                completed_this_month=m["month"],
                completed_this_year=m["year"],
                completed_all_time=m["all_time"],
                completed_in_selected_range=m["selected"],
                legacy_unattributed_completed_count=m["legacy_unattributed"],
                shifts_count=shifts_per_doc[doc.id],
                avg_shift_duration_minutes=avg_mins,
            )
        )

    summary = DoctorPerformanceSummary(
        completed_today=sum(m["today"] for m in doc_metrics.values()),
        completed_this_week=sum(m["week"] for m in doc_metrics.values()),
        completed_this_month=sum(m["month"] for m in doc_metrics.values()),
        completed_this_year=sum(m["year"] for m in doc_metrics.values()),
        completed_all_time=sum(m["all_time"] for m in doc_metrics.values()),
        completed_in_selected_range=sum(m["selected"] for m in doc_metrics.values()),
        legacy_unattributed_completed_count=sum(
            m["legacy_unattributed"] for m in doc_metrics.values()
        ),
        total_shifts=len(shift_items),
        active_shifts=sum(1 for s in shift_items if s.shift_status in (ShiftStatus.OPEN, ShiftStatus.CLOSING)),
        finished_shifts=sum(1 for s in shift_items if s.shift_status == ShiftStatus.FINISHED),
    )

    return AdminDoctorPerformanceResponse(
        clinic_id=clinic.id,
        clinic_name=clinic.name,
        clinic_timezone=str(tz),
        period=period,
        date_from=sel_from,
        date_to=sel_to,
        generated_at=utc_now,
        summary=summary,
        doctors=doctor_items,
        shifts=shift_items,
    )


def render_performance_csv(report: AdminDoctorPerformanceResponse) -> str:
    """
    Serialize AdminDoctorPerformanceResponse to UTF-8 (with BOM) CSV without PII,
    sanitizing every text cell against spreadsheet formula injection.
    """
    tz = get_clinic_zoneinfo(report.clinic_timezone)
    output = io.StringIO()
    output.write("\ufeff")
    writer = csv.writer(output, lineterminator="\n")

    period_label = (
        f"{report.date_from} to {report.date_to}"
        if report.date_from and report.date_to
        else report.period
    )
    gen_local = report.generated_at.astimezone(tz).strftime("%Y-%m-%d %H:%M:%S %Z")

    writer.writerow(["Clinic", sanitize_csv_cell(report.clinic_name)])
    writer.writerow(["Timezone", sanitize_csv_cell(report.clinic_timezone)])
    writer.writerow(["Reporting Period", sanitize_csv_cell(period_label)])
    writer.writerow(["Generated At", sanitize_csv_cell(gen_local)])
    writer.writerow(
        [
            "Total Completed (All-Time)",
            report.summary.completed_all_time,
            "Completed (Selected Range)",
            report.summary.completed_in_selected_range,
            "Legacy Without Completed Timestamp",
            report.summary.legacy_unattributed_completed_count,
        ]
    )
    writer.writerow([])

    writer.writerow(["DOCTOR PERFORMANCE SUMMARY"])
    writer.writerow(
        [
            "Doctor ID",
            "Doctor",
            "Specialization",
            "Room",
            "Current Shift Status",
            "Completed Today",
            "Completed Week",
            "Completed Month",
            "Completed Year",
            "Completed Selected Range",
            "Completed All-Time",
            "Legacy Without Timestamp",
            "Shifts In Period",
            "Avg Shift Duration (min)",
        ]
    )
    for d in report.doctors:
        writer.writerow(
            [
                d.doctor_id,
                sanitize_csv_cell(d.doctor_name),
                sanitize_csv_cell(d.specialization_name),
                sanitize_csv_cell(d.room_number or ""),
                sanitize_csv_cell(d.current_shift_status),
                d.completed_today,
                d.completed_this_week,
                d.completed_this_month,
                d.completed_this_year,
                d.completed_in_selected_range,
                d.completed_all_time,
                d.legacy_unattributed_completed_count,
                d.shifts_count,
                d.avg_shift_duration_minutes if d.avg_shift_duration_minutes is not None else "",
            ]
        )

    writer.writerow([])
    writer.writerow(["SHIFT SESSION HISTORY"])
    writer.writerow(
        [
            "Shift ID",
            "Shift Date",
            "Doctor",
            "Specialization",
            "Room",
            "Shift Status",
            "Paused",
            "Smart Call Mode",
            "Started At",
            "Ended At",
            "Duration (min)",
            "Total Tickets",
            "Completed Visits",
            "Waiting",
            "Called",
            "Serving",
            "Skipped",
            "Cancelled",
        ]
    )
    for s in report.shifts:
        started_str = (
            s.started_at.astimezone(tz).strftime("%Y-%m-%d %H:%M:%S")
            if s.started_at is not None
            else ""
        )
        ended_str = (
            s.ended_at.astimezone(tz).strftime("%Y-%m-%d %H:%M:%S")
            if s.ended_at is not None
            else ""
        )
        dur_min = round(s.duration_seconds / 60.0, 1) if s.duration_seconds is not None else ""
        writer.writerow(
            [
                s.queue_id,
                sanitize_csv_cell(s.queue_date.isoformat()),
                sanitize_csv_cell(s.doctor_name),
                sanitize_csv_cell(s.specialization_name),
                sanitize_csv_cell(s.room_number or ""),
                sanitize_csv_cell(s.shift_status.value),
                "YES" if s.is_paused else "NO",
                sanitize_csv_cell(s.smart_call_mode.value),
                sanitize_csv_cell(started_str),
                sanitize_csv_cell(ended_str),
                dur_min,
                s.total_tickets,
                s.completed_count,
                s.waiting_count,
                s.called_count,
                s.serving_count,
                s.skipped_count,
                s.cancelled_count,
            ]
        )

    return output.getvalue()
