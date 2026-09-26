export interface PublicDisplayClinic {
  id: number;
  name: string;
}

export interface PublicDisplayDoctor {
  id: number;
  full_name: string;
  room_number: string | null;
}

export interface PublicDisplaySpecialization {
  id: number;
  name: string;
}

export interface PublicDisplayTicket {
  ticket_number: number;
}

export interface PublicDisplayQueue {
  doctor: PublicDisplayDoctor;
  specialization: PublicDisplaySpecialization;
  is_paused: boolean;
  called_ticket: PublicDisplayTicket | null;
  waiting_tickets: PublicDisplayTicket[];
}

export interface PublicDisplayResponse {
  clinic: PublicDisplayClinic;
  queues: PublicDisplayQueue[];
}
