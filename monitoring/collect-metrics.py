#!/usr/bin/env python3
"""
Collect metrics from distributed Arroyo cluster
"""

import time
import json
import requests
import argparse
import sys
import os
from datetime import datetime
from typing import Dict, List, Any
import yaml

class DistributedMetricsCollector:
    def __init__(self, config_path: str):
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.controller_ip = self.config['cluster']['controller']['ip']
        self.api_port = 8001
        self.api_url = f"http://{self.controller_ip}:{self.api_port}"
        
    def get_cluster_status(self) -> Dict[str, Any]:
        """Get overall cluster status"""
        try:
            # Get controller health
            controller_health = requests.get(f"{self.api_url}/health").json()
            
            # Get worker status
            workers_resp = requests.get(f"{self.api_url}/api/v1/workers")
            workers = workers_resp.json() if workers_resp.status_code == 200 else []
            
            return {
                "controller_health": controller_health,
                "workers": workers,
                "worker_count": len(workers),
                "timestamp": datetime.utcnow().isoformat()
            }
        except Exception as e:
            return {"error": str(e)}
    
    def get_pipeline_metrics(self, pipeline_id: str) -> Dict[str, Any]:
        """Get metrics for a specific pipeline"""
        try:
            # Get pipeline info
            pipeline_resp = requests.get(f"{self.api_url}/api/v1/pipelines/{pipeline_id}")
            pipeline_info = pipeline_resp.json() if pipeline_resp.status_code == 200 else {}
            
            # Get jobs for this pipeline
            jobs_resp = requests.get(f"{self.api_url}/api/v1/pipelines/{pipeline_id}/jobs")
            jobs_data = jobs_resp.json()
            jobs = jobs_data.get('data', []) if jobs_resp.status_code == 200 else []
            
            # Get metrics for running job
            metrics = {}
            for job in jobs:
                if job.get('state') == 'Running':
                    job_id = job['id']
                    metrics_resp = requests.get(f"{self.api_url}/api/v1/jobs/{job_id}/metrics")
                    if metrics_resp.status_code == 200:
                        metrics = metrics_resp.json()
                    break
            
            return {
                "pipeline_id": pipeline_id,
                "pipeline_name": pipeline_info.get('name', 'unknown'),
                "jobs": jobs,
                "metrics": metrics,
                "timestamp": datetime.utcnow().isoformat()
            }
        except Exception as e:
            return {"pipeline_id": pipeline_id, "error": str(e)}
    
    def get_all_pipelines(self) -> List[str]:
        """Get list of all pipeline IDs"""
        try:
            resp = requests.get(f"{self.api_url}/api/v1/pipelines")
            if resp.status_code == 200:
                pipelines_data = resp.json()
                pipelines = pipelines_data.get('data', [])
                return [p['id'] for p in pipelines]
            return []
        except:
            return []
    
    def collect_all_metrics(self) -> Dict[str, Any]:
        """Collect metrics from entire cluster"""
        cluster_status = self.get_cluster_status()
        pipeline_ids = self.get_all_pipelines()
        
        pipeline_metrics = []
        for pid in pipeline_ids:
            metrics = self.get_pipeline_metrics(pid)
            pipeline_metrics.append(metrics)
        
        return {
            "cluster": cluster_status,
            "pipelines": pipeline_metrics,
            "summary": {
                "total_pipelines": len(pipeline_ids),
                "active_workers": cluster_status.get("worker_count", 0),
                "timestamp": datetime.utcnow().isoformat()
            }
        }
    
    def monitor_continuous(self, interval: int = 5, output_file: str = None):
        """Continuously monitor and optionally save metrics"""
        print(f"Starting continuous monitoring (interval: {interval}s)")
        print(f"Controller: {self.controller_ip}")
        if output_file:
            print(f"Saving to: {output_file}")
        print("-" * 80)
        
        all_metrics = []
        
        try:
            while True:
                metrics = self.collect_all_metrics()
                
                # Display summary
                print(f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]")
                print(f"Workers: {metrics['summary']['active_workers']}")
                print(f"Pipelines: {metrics['summary']['total_pipelines']}")
                
                # Display pipeline metrics
                for pm in metrics['pipelines']:
                    if 'error' not in pm:
                        pipeline_name = pm['pipeline_name']
                        pipeline_metrics = pm.get('metrics', {})
                        
                        events = pipeline_metrics.get('events_processed', 0)
                        rate = pipeline_metrics.get('events_per_second', 0)
                        
                        print(f"  {pipeline_name}: {events:,} events @ {rate:,.0f} events/sec")
                
                # Save to file if specified
                if output_file:
                    all_metrics.append(metrics)
                    with open(output_file, 'w') as f:
                        json.dump(all_metrics, f, indent=2)
                
                time.sleep(interval)
                
        except KeyboardInterrupt:
            print("\n\nMonitoring stopped.")
            if output_file and all_metrics:
                print(f"Metrics saved to: {output_file}")

def main():
    parser = argparse.ArgumentParser(description='Monitor distributed Arroyo cluster')
    parser.add_argument('--config', '-c', 
                        default='../config/cluster-topology.yaml',
                        help='Path to cluster configuration file')
    parser.add_argument('--interval', '-i', 
                        type=int, 
                        default=5,
                        help='Monitoring interval in seconds')
    parser.add_argument('--output', '-o',
                        help='Output file for metrics (JSON format)')
    parser.add_argument('--once', 
                        action='store_true',
                        help='Collect metrics once and exit')
    
    args = parser.parse_args()
    
    # Check if config file exists
    if not os.path.exists(args.config):
        print(f"Error: Configuration file not found: {args.config}")
        sys.exit(1)
    
    collector = DistributedMetricsCollector(args.config)
    
    if args.once:
        metrics = collector.collect_all_metrics()
        print(json.dumps(metrics, indent=2))
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(metrics, f, indent=2)
    else:
        collector.monitor_continuous(args.interval, args.output)

if __name__ == "__main__":
    main()