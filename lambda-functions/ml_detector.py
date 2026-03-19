"""
ML-Based Threat Detection Lambda Function
Analyzes CloudWatch logs and detects threats using ML patterns
"""
import json
import boto3
import re
from datetime import datetime, timedelta

logs_client = boto3.client('logs')

# ML detection patterns (simplified for Lambda)
THREAT_PATTERNS = {
    'crypto_mining': {
        'keywords': ['mining', 'xmrig', 'pool', 'cryptocurrency', 'bitcoin', 'monero'],
        'severity': 'CRITICAL',
        'confidence': 0.95
    },
    'data_exfiltration': {
        'keywords': ['exfiltration', 'download', 'bucket', 'sensitive', 'dump'],
        'severity': 'HIGH',
        'confidence': 0.90
    },
    'privilege_escalation': {
        'keywords': ['privilege', 'escalation', 'admin', 'root', 'assume-role'],
        'severity': 'HIGH',
        'confidence': 0.88
    },
    'lateral_movement': {
        'keywords': ['ssh', 'rdp', 'network', 'scan', 'enumerate'],
        'severity': 'MEDIUM',
        'confidence': 0.85
    },
    'persistence': {
        'keywords': ['cron', 'systemd', 'backdoor', 'scheduled'],
        'severity': 'HIGH',
        'confidence': 0.87
    }
}

def analyze_log_entry(log_message):
    """Analyze a single log entry for threats"""
    threats_detected = []
    
    log_lower = log_message.lower()
    
    for threat_type, pattern in THREAT_PATTERNS.items():
        matches = sum(1 for keyword in pattern['keywords'] if keyword in log_lower)
        
        if matches > 0:
            confidence = pattern['confidence'] * (matches / len(pattern['keywords']))
            threats_detected.append({
                'threat_type': threat_type,
                'severity': pattern['severity'],
                'confidence': round(confidence, 2),
                'matches': matches,
                'total_keywords': len(pattern['keywords'])
            })
    
    return threats_detected

def lambda_handler(event, context):
    """Main Lambda handler"""
    
    # Query attack simulation logs from last 5 minutes
    
    end_time = int(datetime.now().timestamp() * 1000)
    start_time = int((datetime.now() - timedelta(minutes=5)).timestamp() * 1000)
    
    try:
        # Query attack simulation logs
        response = logs_client.filter_log_events(
            logGroupName='/aws/ec2/attack-simulations',
            startTime=start_time,
            endTime=end_time,
            limit=100
        )
        
        all_detections = []
        
        for event in response.get('events', []):
            message = event.get('message', '')
            threats = analyze_log_entry(message)
            
            for threat in threats:
                detection = {
                    'timestamp': datetime.fromtimestamp(event['timestamp'] / 1000).isoformat(),
                    'threat_type': threat['threat_type'],
                    'severity': threat['severity'],
                    'confidence': threat['confidence'],
                    'log_stream': event.get('logStreamName', 'unknown'),
                    'message_preview': message[:200]
                }
                all_detections.append(detection)
        
        # Write ML detection results to CloudWatch Logs
        if all_detections:
            log_stream_name = f"ml-detection-{datetime.now().strftime('%Y-%m-%d')}"
            
            try:
                logs_client.create_log_stream(
                    logGroupName='/aws/ml-detection/results',
                    logStreamName=log_stream_name
                )
            except logs_client.exceptions.ResourceAlreadyExistsException:
                pass
            
            # Write each detection
            log_events = []
            for detection in all_detections:
                log_events.append({
                    'timestamp': int(datetime.now().timestamp() * 1000),
                    'message': json.dumps(detection)
                })
            
            if log_events:
                logs_client.put_log_events(
                    logGroupName='/aws/ml-detection/results',
                    logStreamName=log_stream_name,
                    logEvents=log_events
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ML detection complete',
                'threats_detected': len(all_detections),
                'detections': all_detections
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
