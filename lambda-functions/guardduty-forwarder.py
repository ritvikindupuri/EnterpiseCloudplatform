#!/usr/bin/env python3
"""
GuardDuty Findings Forwarder to CloudWatch
Forwards AWS GuardDuty findings to CloudWatch Logs and triggers incident response
"""
import json
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """Lambda handler for GuardDuty findings - logs to CloudWatch"""
    
    detail = event.get('detail', {})
    
    # Log finding to CloudWatch in structured format
    finding_summary = {
        'timestamp': detail.get('updatedAt', datetime.utcnow().isoformat()),
        'finding_id': detail.get('id'),
        'type': detail.get('type'),
        'severity': detail.get('severity'),
        'confidence': detail.get('confidence'),
        'account_id': detail.get('accountId'),
        'region': detail.get('region'),
        'description': detail.get('description'),
        'resource': detail.get('resource', {}),
        'service': detail.get('service', {})
    }
    
    logger.info(f"GuardDuty Finding: {json.dumps(finding_summary, indent=2)}")
    
    # Trigger automated response for critical findings
    if detail.get('severity', 0) >= 7.0:
        logger.warning(f"CRITICAL FINDING DETECTED: {detail.get('type')}")
        trigger_incident_response(detail)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Finding logged successfully')
    }

def trigger_incident_response(finding):
    """Trigger automated incident response for critical findings"""
    import boto3
    
    lambda_client = boto3.client('lambda')
    
    # Determine response action based on finding type
    finding_type = finding.get('type', '')
    
    payload = {
        'finding_id': finding.get('id'),
        'severity': finding.get('severity'),
        'type': finding_type
    }
    
    if 'UnauthorizedAccess' in finding_type or 'Backdoor' in finding_type:
        # Isolate compromised instance
        resource = finding.get('resource', {})
        if resource.get('resourceType') == 'Instance':
            instance_id = resource.get('instanceDetails', {}).get('instanceId')
            payload['alert_type'] = 'lateral_movement'
            payload['instance_id'] = instance_id
            
            logger.info(f"Triggering incident response for instance: {instance_id}")
            lambda_client.invoke(
                FunctionName='cloud-security-incident-response',
                InvocationType='Event',
                Payload=json.dumps(payload)
            )
    
    elif 'CryptoCurrency' in finding_type:
        # Terminate mining process
        resource = finding.get('resource', {})
        if resource.get('resourceType') == 'Instance':
            instance_id = resource.get('instanceDetails', {}).get('instanceId')
            payload['alert_type'] = 'malicious_process'
            payload['instance_id'] = instance_id
            payload['process_name'] = 'xmrig|minerd|cpuminer'
            
            logger.info(f"Triggering crypto mining response for instance: {instance_id}")
            lambda_client.invoke(
                FunctionName='cloud-security-incident-response',
                InvocationType='Event',
                Payload=json.dumps(payload)
            )
