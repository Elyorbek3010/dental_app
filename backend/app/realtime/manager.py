import logging
from collections import defaultdict
from typing import Any
from starlette.websockets import WebSocket, WebSocketState

logger = logging.getLogger(__name__)


class ConnectionManager:
    """
    Manages in-memory WebSocket connections grouped by clinic_id.
    Designed for single-process FastAPI public waiting-room display connections.
    """

    def __init__(self) -> None:
        self._connections: dict[int, set[WebSocket]] = defaultdict(set)

    async def connect(self, clinic_id: int, websocket: WebSocket) -> None:
        """Accept the WebSocket and register it for the specified clinic."""
        if websocket.client_state == WebSocketState.CONNECTING:
            await websocket.accept()
        self._connections[clinic_id].add(websocket)
        logger.info(
            "WebSocket connected for clinic %s (total for clinic: %s)",
            clinic_id,
            len(self._connections[clinic_id]),
        )

    def disconnect(self, clinic_id: int, websocket: WebSocket) -> None:
        """Unregister a WebSocket connection for the specified clinic."""
        if clinic_id in self._connections:
            self._connections[clinic_id].discard(websocket)
            if not self._connections[clinic_id]:
                del self._connections[clinic_id]
        logger.info("WebSocket disconnected for clinic %s", clinic_id)

    async def broadcast(self, clinic_id: int, message: dict[str, Any]) -> None:
        """
        Broadcast a message to all active WebSocket connections for a clinic.
        Dead or failed connections are cleaned up safely without disrupting other connections.
        """
        try:
            sockets = list(self._connections.get(clinic_id, set()))
            if not sockets:
                return

            dead_sockets: list[WebSocket] = []
            for socket in sockets:
                try:
                    await socket.send_json(message)
                except Exception as exc:
                    logger.warning(
                        "Failed to broadcast message to WebSocket in clinic %s: %s",
                        clinic_id,
                        exc,
                    )
                    dead_sockets.append(socket)

            for dead_socket in dead_sockets:
                self.disconnect(clinic_id, dead_socket)
        except Exception as exc:
            logger.error("Unexpected error in broadcast for clinic %s: %s", clinic_id, exc)

    def get_connection_count(self, clinic_id: int) -> int:
        """Return the number of active connections for a clinic."""
        return len(self._connections.get(clinic_id, set()))

    def get_total_connections(self) -> int:
        """Return total number of active connections across all clinics."""
        return sum(len(sockets) for sockets in self._connections.values())


manager = ConnectionManager()


def notify_display_update(
    clinic_id: int,
    background_tasks: Any = None,
    queue_id: int | None = None,
) -> None:
    """
    Schedule a privacy-safe broadcast for a clinic.
    Sends 'display_updated' for Public Display / Reception web clients,
    and 'queue_updated' (with queue_id) for Patient mobile/web preview clients.
    Uses FastAPI BackgroundTasks if provided; falls back to current event loop or no-op.
    Guaranteed non-blocking and safe: never raises an exception.
    """
    import asyncio

    display_message: dict[str, Any] = {
        "type": "display_updated",
        "clinic_id": clinic_id,
    }
    if queue_id is not None:
        display_message["queue_id"] = queue_id

    queue_message: dict[str, Any] = {
        "type": "queue_updated",
        "clinic_id": clinic_id,
        "queue_id": queue_id,
    }

    async def _broadcast_both() -> None:
        await manager.broadcast(clinic_id, display_message)
        await manager.broadcast(clinic_id, queue_message)

    try:
        if background_tasks is not None and hasattr(background_tasks, "add_task"):
            background_tasks.add_task(_broadcast_both)
            return

        loop = asyncio.get_running_loop()
        loop.create_task(_broadcast_both())
    except RuntimeError:
        # No active event loop in current thread (e.g. standalone synchronous tests)
        pass
    except Exception as exc:
        logger.error(
            "Error scheduling display/queue update for clinic %s: %s",
            clinic_id,
            exc,
        )


notify_queue_update = notify_display_update

