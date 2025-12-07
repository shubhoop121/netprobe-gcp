import os
import logging
from google.cloud import compute_v1
from google.api_core import exceptions

logger = logging.getLogger(__name__)

def block_ip_in_armor(ip_address):
    """
    Directly updates Cloud Armor Rule 500 to add the IP.
    """
    # 1. Local Dev Safety
    if os.environ.get('PROJECT_ID') == 'local-dev' or not os.environ.get('DB_HOST'):
        logger.info(f"--- [MOCK ARMOR] Blocking IP: {ip_address} ---")
        return {"status": "mock-success", "id": "local-op-123"}

    project_id = os.environ.get("PROJECT_ID", "netprobe-473119")
    policy_name = "netprobe-api-security-policy"
    priority = 500  # The priority of our Blocklist Rule

    # Ensure CIDR format
    if "/" not in ip_address:
        ip_to_block = f"{ip_address}/32"
    else:
        ip_to_block = ip_address

    logger.info(f"--- [REAL ARMOR] Patching Rule {priority} to add {ip_to_block} ---")

    try:
        client = compute_v1.SecurityPoliciesClient()

        # A. Fetch policy to get current rule fingerprint
        # This prevents race conditions (optimistic locking)
        policy = client.get(project=project_id, security_policy=policy_name)
        
        # Find Rule 500
        target_rule = None
        for rule in policy.rules:
            if rule.priority == priority:
                target_rule = rule
                break
        
        if not target_rule:
            return {"status": "error", "message": f"Rule {priority} not found"}

        # B. Check if IP exists, otherwise append
        existing_ips = list(target_rule.match.config.src_ip_ranges)
        if ip_to_block in existing_ips:
            logger.warning(f"IP {ip_to_block} is already blocked.")
            return {"status": "already-exists", "message": "IP is already blocked"}

        existing_ips.append(ip_to_block)

        # C. Prepare the Rule Resource
        updated_rule = compute_v1.SecurityPolicyRule(
            priority=priority,
            match=compute_v1.SecurityPolicyRuleMatcher(
                versioned_expr="SRC_IPS_V1",
                config=compute_v1.SecurityPolicyRuleMatcherConfig(
                    src_ip_ranges=existing_ips
                )
            )
        )

        # D. Construct the Proper Request Object (Fixes the editor error)
        request = compute_v1.PatchRuleSecurityPolicyRequest(
            project=project_id,
            security_policy=policy_name,
            priority=priority,
            security_policy_rule_resource=updated_rule
        )

        # Execute
        operation = client.patch_rule(request=request)
        
        logger.info(f"--- [REAL ARMOR] Operation started: {operation.name} ---")

        return {
            "status": "success", 
            "operation": operation.name,
            "blocked_ip": ip_to_block,
            "total_blocked_ips": len(existing_ips)
        }

    except Exception as e:
        logger.error(f"Cloud Armor Rule Update Failed: {e}", exc_info=True)
        # Re-raise so the API returns 500
        raise e