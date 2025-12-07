# apps/api/app/cloud_armor.py
import os
import logging
import uuid
from google.cloud import network_security_v1
from google.api_core import exceptions

logger = logging.getLogger(__name__)

def block_ip_in_armor(ip_address):
    """
    Adds an IP to the Cloud Armor global address group.
    """
    # 1. Safety Check for Local Dev
    # If we are running locally (no DB_HOST usually means local), don't hit Google APIs
    if os.environ.get('PROJECT_ID') == 'local-dev' or not os.environ.get('DB_HOST'):
        logger.info(f"--- [MOCK ARMOR] Blocking IP: {ip_address} ---")
        return {"status": "mock-success", "id": "local-op-123"}

    # 2. Production Config
    project_id = os.environ.get("PROJECT_ID", "netprobe-473119")
    location = "global"
    group_name = "netprobe-global-blocklist"

    # Full Resource Name
    group_full_name = f"projects/{project_id}/locations/{location}/addressGroups/{group_name}"

    # Ensure CIDR format (Address Groups require /32 for single IPs)
    if "/" not in ip_address:
        ip_to_block = f"{ip_address}/32"
    else:
        ip_to_block = ip_address

    logger.info(f"--- [REAL ARMOR] Adding {ip_to_block} to {group_name} ---")

    try:
        client = network_security_v1.NetworkSecurityClient()
        
        # Prepare the request
        request = network_security_v1.AddAddressGroupItemsRequest(
            address_group=group_full_name,
            items=[ip_to_block],
            request_id=str(uuid.uuid4()) # Idempotency key
        )

        # Execute (Returns a Long-Running Operation)
        operation = client.add_address_group_items(request=request)
        
        # We return the Operation ID so the frontend could poll it if needed
        # But for now, we just fire-and-forget to keep the UI snappy.
        logger.info(f"--- [REAL ARMOR] Operation started: {operation.operation.name} ---")
        
        return {
            "status": "success", 
            "operation": operation.operation.name,
            "target": group_name,
            "blocked_ip": ip_to_block
        }

    except exceptions.AlreadyExists:
        logger.warning(f"IP {ip_to_block} is already in the blocklist.")
        return {"status": "already-exists", "message": "IP is already blocked"}
        
    except Exception as e:
        logger.error(f"Cloud Armor API Failed: {e}", exc_info=True)
        # Re-raise so the API returns 500
        raise e