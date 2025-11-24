import os
import logging

logger = logging.getLogger(__name__)

def block_ip_in_armor(ip_address):
    """
    Adds an IP to the Cloud Armor global address group.
    Currently MOCKED for local development.
    """
    # 1. Dev/Local Mode Check
    # (We check DB_HOST because in local dev it is usually 'db', in prod it is an IP)
    if os.environ.get('DB_HOST') == 'db' or os.environ.get('PROJECT_ID') == 'local-dev':
        logger.info(f"--- [MOCK ARMOR] Blocking IP: {ip_address} ---")
        return {"status": "mock-success", "id": "local-op-123"}

    # 2. Production Mode (Real API Call)
    # TODO: Implement the actual google-cloud-network-security call here
    # later in Phase 3.3. For now, we log the intent.
    logger.info(f"--- [REAL ARMOR STUB] Would block IP {ip_address} in Cloud Armor ---")
    return {"status": "simulated-success"}