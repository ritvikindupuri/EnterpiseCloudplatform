#!/usr/bin/env python3
"""
Standalone ML Training - No Elasticsearch Required
Trains models on synthetic security data
"""
import numpy as np
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.preprocessing import StandardScaler
import joblib
import os
from datetime import datetime, timedelta

def generate_security_events(n_samples=10000):
    """Generate realistic synthetic security events"""
    print(f"Generating {n_samples} realistic security events...")
    
    events = []
    
    # Benign events (70%)
    for i in range(int(n_samples * 0.7)):
        hour = np.random.randint(8, 18)  # Business hours
        events.append({
            'hour': hour,
            'weekday': np.random.randint(0, 5),  # Weekdays
            'is_weekend': 0,
            'is_offhours': 0,
            'is_failure': 0,
            'is_suspicious_action': 0,
            'network_bytes': np.random.randint(100, 10000),
            'network_packets': np.random.randint(10, 100),
            'username_length': np.random.randint(5, 15),
            'has_suspicious_username': 0,
            'is_internal_ip': 1,
            'action_length': np.random.randint(10, 30),
            'label': 0  # Benign
        })
    
    # Malicious events (30%)
    for i in range(int(n_samples * 0.3)):
        hour = np.random.choice([2, 3, 4, 22, 23])  # Off-hours
        events.append({
            'hour': hour,
            'weekday': np.random.randint(0, 7),
            'is_weekend': np.random.randint(0, 2),
            'is_offhours': 1,
            'is_failure': np.random.randint(0, 2),
            'is_suspicious_action': 1,
            'network_bytes': np.random.randint(10000, 1000000),
            'network_packets': np.random.randint(100, 10000),
            'username_length': np.random.randint(3, 8),
            'has_suspicious_username': 1,
            'is_internal_ip': 0,
            'action_length': np.random.randint(20, 50),
            'label': 1  # Malicious
        })
    
    print(f"✓ Generated {len(events)} events")
    print(f"  Benign: {sum(1 for e in events if e['label'] == 0)}")
    print(f"  Malicious: {sum(1 for e in events if e['label'] == 1)}")
    
    return events

def extract_features(events):
    """Convert events to feature matrix"""
    X = []
    y = []
    
    for event in events:
        features = [
            event['hour'],
            event['weekday'],
            event['is_weekend'],
            event['is_offhours'],
            event['is_failure'],
            event['is_suspicious_action'],
            event['network_bytes'],
            event['network_packets'],
            event['username_length'],
            event['has_suspicious_username'],
            event['is_internal_ip'],
            event['action_length']
        ]
        X.append(features)
        y.append(event['label'])
    
    return np.array(X), np.array(y)

def train_models():
    """Train ML models"""
    print("\n" + "="*60)
    print("TRAINING ML MODELS ON SECURITY DATA")
    print("="*60 + "\n")
    
    # Generate data
    events = generate_security_events(10000)
    
    # Extract features
    print("\nExtracting features...")
    X, y = extract_features(events)
    print(f"✓ Feature matrix shape: {X.shape}")
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    print(f"Training set: {X_train.shape[0]} samples")
    print(f"Test set: {X_test.shape[0]} samples")
    
    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    
    # Define models
    models = {
        'Random Forest': RandomForestClassifier(
            n_estimators=200, 
            max_depth=20, 
            random_state=42,
            n_jobs=-1
        ),
        'Gradient Boosting': GradientBoostingClassifier(
            n_estimators=100, 
            random_state=42
        ),
        'Neural Network': MLPClassifier(
            hidden_layer_sizes=(100, 50, 25), 
            max_iter=500, 
            random_state=42
        )
    }
    
    trained_models = {}
    results = {}
    
    # Train each model
    for name, model in models.items():
        print(f"\n{'='*60}")
        print(f"Training {name}...")
        print('='*60)
        
        model.fit(X_train_scaled, y_train)
        
        # Predictions
        y_pred = model.predict(X_test_scaled)
        accuracy = accuracy_score(y_test, y_pred)
        
        print(f"\n✓ {name} Training Complete")
        print(f"Accuracy: {accuracy:.2%}")
        
        print(f"\nClassification Report:")
        print(classification_report(y_test, y_pred, target_names=['Benign', 'Malicious']))
        
        print(f"\nConfusion Matrix:")
        cm = confusion_matrix(y_test, y_pred)
        print(f"                Predicted")
        print(f"                Benign  Malicious")
        print(f"Actual Benign   {cm[0][0]:6d}  {cm[0][1]:9d}")
        print(f"       Malicious{cm[1][0]:6d}  {cm[1][1]:9d}")
        
        trained_models[name] = model
        results[name] = {
            'accuracy': accuracy,
            'confusion_matrix': cm.tolist()
        }
    
    # Save models
    os.makedirs('models', exist_ok=True)
    joblib.dump(trained_models, 'models/real_trained_models.pkl')
    joblib.dump(scaler, 'models/real_scaler.pkl')
    
    print("\n" + "="*60)
    print("TRAINING COMPLETE")
    print("="*60)
    print(f"\nModels saved to:")
    print(f"  ✓ models/real_trained_models.pkl")
    print(f"  ✓ models/real_scaler.pkl")
    
    print(f"\nModel Performance Summary:")
    for name, result in results.items():
        print(f"  {name}: {result['accuracy']:.2%} accuracy")
    
    return trained_models, scaler

if __name__ == '__main__':
    train_models()
