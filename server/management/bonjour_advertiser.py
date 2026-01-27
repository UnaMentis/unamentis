"""
UnaMentis Bonjour/mDNS Service Advertisement

Advertises the UnaMentis server on the local network using mDNS (Bonjour),
allowing iOS and Android clients to automatically discover the server.

Service type: _unamentis._tcp.local.
"""

import logging
import socket
from typing import Optional

logger = logging.getLogger(__name__)

# Check if zeroconf is available
try:
    from zeroconf import Zeroconf, ServiceInfo
    from zeroconf.asyncio import AsyncZeroconf
    ZEROCONF_AVAILABLE = True
except ImportError:
    ZEROCONF_AVAILABLE = False
    logger.info("zeroconf not installed. Install with: pip install zeroconf")


class BonjourAdvertiser:
    """
    Advertises UnaMentis server via mDNS/Bonjour for zero-config discovery.

    Usage:
        advertiser = BonjourAdvertiser(gateway_port=11400, management_port=8766)
        await advertiser.start()
        # ... server runs ...
        await advertiser.stop()
    """

    SERVICE_TYPE = "_unamentis._tcp.local."

    def __init__(
        self,
        gateway_port: int = 11400,
        management_port: int = 8766,
        service_name: Optional[str] = None
    ):
        """
        Initialize the Bonjour advertiser.

        Args:
            gateway_port: The port the UnaMentis gateway runs on
            management_port: The port the management API runs on
            service_name: Optional custom service name (defaults to hostname)
        """
        self.gateway_port = gateway_port
        self.management_port = management_port
        self.service_name = service_name or self._get_service_name()
        self._zeroconf: Optional["AsyncZeroconf"] = None
        self._service_info: Optional["ServiceInfo"] = None
        self._is_running = False

    async def start(self) -> bool:
        """
        Start advertising the service via mDNS.

        Returns:
            True if advertising started successfully, False otherwise
        """
        if not ZEROCONF_AVAILABLE:
            logger.warning("Bonjour advertising disabled: zeroconf not installed")
            return False

        if self._is_running:
            logger.debug("Bonjour advertiser already running")
            return True

        try:
            local_ip = self._get_local_ip()
            if not local_ip:
                logger.warning("Could not determine local IP, Bonjour advertising disabled")
                return False

            hostname = socket.gethostname()

            # Create service info with metadata in TXT record
            self._service_info = ServiceInfo(
                self.SERVICE_TYPE,
                f"{self.service_name}.{self.SERVICE_TYPE}",
                addresses=[socket.inet_aton(local_ip)],
                port=self.gateway_port,
                properties={
                    "version": "1.0",
                    "gateway_port": str(self.gateway_port),
                    "management_port": str(self.management_port),
                    "hostname": hostname,
                    "platform": "macos",
                },
            )

            # Create and start async zeroconf
            self._zeroconf = AsyncZeroconf()
            await self._zeroconf.async_register_service(self._service_info)

            self._is_running = True
            logger.info(
                f"Bonjour: Advertising '{self.service_name}' at {local_ip}:{self.gateway_port}"
            )
            return True

        except Exception as e:
            logger.error(f"Failed to start Bonjour advertising: {e}")
            await self._cleanup()
            return False

    async def stop(self):
        """Stop advertising the service."""
        if not self._is_running:
            return

        await self._cleanup()
        logger.info("Bonjour: Stopped advertising")

    async def _cleanup(self):
        """Clean up zeroconf resources."""
        try:
            if self._zeroconf and self._service_info:
                await self._zeroconf.async_unregister_service(self._service_info)
            if self._zeroconf:
                await self._zeroconf.async_close()
        except Exception as e:
            logger.debug(f"Cleanup error (non-fatal): {e}")
        finally:
            self._zeroconf = None
            self._service_info = None
            self._is_running = False

    @property
    def is_running(self) -> bool:
        """Check if the advertiser is currently running."""
        return self._is_running

    def _get_service_name(self) -> str:
        """Generate a service name based on hostname."""
        hostname = socket.gethostname()
        # Remove .local suffix if present
        if hostname.endswith(".local"):
            hostname = hostname[:-6]
        return f"UnaMentis-{hostname}"

    def _get_local_ip(self) -> Optional[str]:
        """
        Get the local IP address of this machine.

        Uses a UDP socket to determine the outbound IP address,
        which is more reliable than parsing network interfaces.
        """
        try:
            # Create a UDP socket and connect to an external address
            # This doesn't actually send data, just determines the route
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(1.0)  # Prevent blocking event loop on slow networks
            try:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
            finally:
                s.close()
        except (OSError, socket.timeout):
            pass

        # Fallback: try to find en0 interface
        try:
            import netifaces
            for iface in ["en0", "en1", "eth0"]:
                try:
                    addrs = netifaces.ifaddresses(iface)
                    if netifaces.AF_INET in addrs:
                        return addrs[netifaces.AF_INET][0]["addr"]
                except (ValueError, KeyError):
                    continue
        except ImportError:
            pass

        return None


# Convenience function for use in server startup
async def start_bonjour_advertising(
    gateway_port: int = 11400,
    management_port: int = 8766
) -> Optional[BonjourAdvertiser]:
    """
    Start Bonjour advertising and return the advertiser instance.

    Args:
        gateway_port: Port for the UnaMentis gateway
        management_port: Port for the management API

    Returns:
        BonjourAdvertiser instance if successful, None otherwise
    """
    advertiser = BonjourAdvertiser(
        gateway_port=gateway_port,
        management_port=management_port
    )
    if await advertiser.start():
        return advertiser
    return None
