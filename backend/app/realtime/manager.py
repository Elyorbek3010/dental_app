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


def notify_display_update(clinic_id: int, background_tasks: Any = None) -> None:
    """
    Schedule a privacy-safe 'display_updated' broadcast for a clinic.
    Uses FastAPI BackgroundTasks if provided; falls back to current event loop or no-op.
    Guaranteed non-blocking and safe: never raises an exception.
    """
    import asyncio

    message = {
        "type": "display_updated",
        "clinic_id": clinic_id,
    }

    try:
        if background_tasks is not None and hasattr(background_tasks, "add_task"):
            background_tasks.add_task(manager.broadcast, clinic_id, message)
            return

        loop = asyncio.get_running_loop()
        loop.create_task(manager.broadcast(clinic_id, message))
    except RuntimeError:
        # No active event loop in current thread (e.g. standalone synchronous tests)
        pass
    except Exception as exc:
        logger.error("Error scheduling display update for clinic %s: %s", clinic_id, exc)

