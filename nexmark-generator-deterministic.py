#!/usr/bin/env python
"""
THis generator creates a deterministic stream of Nexmark events (Person, Auction, Bid)
and sends them to Kafka topics. The event generation is based on a fixed algorithm
that ensures the same sequence of events is produced each time for a given starting
event ID.

This generator is inspired by the official Nexmark generator (https://github.com/nexmark/nexmark) but rewritten in python.


"""

import json
import time
import sys
import hashlib
import multiprocessing
from datetime import datetime, timezone
from confluent_kafka import Producer
import random
import os

# Constants from official Nexmark
FIRST_PERSON_ID = 1000
FIRST_AUCTION_ID = 1000
FIRST_CATEGORY_ID = 10

# Event proportions (1:3:46 ratio)
PERSON_PROPORTION = 1
AUCTION_PROPORTION = 3
BID_PROPORTION = 46
TOTAL_PROPORTION = PERSON_PROPORTION + AUCTION_PROPORTION + BID_PROPORTION  # 50

# Hot item/seller/bidder ratios (from official generator)
HOT_SELLER_RATIO = 100
HOT_AUCTION_RATIO = 100
HOT_BIDDER_RATIO = 100
HOT_CHANNELS_RATIO = 2

# Configuration
NUM_CATEGORIES = 5
NUM_PEOPLE_CARDINALITY = 1000
NUM_AUCTIONS_CARDINALITY = 1000
NUM_ACTIVE_PEOPLE = 1000
NUM_IN_FLIGHT_AUCTIONS = 100

# Pre-defined data
CHANNELS = ["Google", "Facebook", "Baidu", "Apple"]
HOT_CHANNELS = CHANNELS[:4]
FIRST_NAMES = ["Peter", "Paul", "Luke", "John", "Saul", "Vicky", "Kate", "Julie", "Sarah", "Deiter", "Johann"]
LAST_NAMES = ["Shultz", "Abrams", "Spencer", "White", "Bartels", "Walton", "Smith", "Jones", "Noris"]
US_CITIES = ["Phoenix", "Los Angeles", "San Francisco", "Boise", "Portland", "Bend", "Redmond", "Seattle", "Kent", "Spokane"]
US_STATES = ["az", "ca", "ca", "id", "or", "or", "wa", "wa", "wa", "wa"]
AU_CITIES = ["Sydney", "Melbourne", "Brisbane", "Perth", "Adelaide"]
AU_STATES = ["nsw", "vic", "qld", "wa", "sa"]

def hash_id(event_id):
    """Create deterministic hash from event ID."""
    return int(hashlib.md5(str(event_id).encode()).hexdigest()[:8], 16)

def next_string(event_id, max_length):
    """Generate deterministic string based on event ID."""
    rng = random.Random(event_id)
    length = rng.randint(max_length // 2, max_length)
    return ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(length))

def format_timestamp(timestamp_ms, use_iso=False):
    """Convert millisecond timestamp to desired format."""
    if use_iso:
        # Format as Berlin time (local time)
        dt = datetime.fromtimestamp(timestamp_ms / 1000.0)
        # Return ISO format without suffix - Berlin time
        return dt.strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3]
    return timestamp_ms

class NexmarkGenerator:
    """Deterministic Nexmark event generator."""
    
    def __init__(self, events_per_second=10000, first_event_id=0, use_iso=False, use_berlin_time=False):
        self.events_per_second = events_per_second
        self.inter_event_delay_us = 1_000_000.0 / events_per_second
        self.first_event_id = first_event_id
        self.event_count = 0
        # Use current time, add 2 hours for Berlin time if requested
        self.base_time = int(time.time() * 1000)
        if use_berlin_time:
            self.base_time += 2 * 60 * 60 * 1000  # Add 2 hours in milliseconds
        self.use_iso = use_iso
        self.use_berlin_time = use_berlin_time
        
    def get_event_timestamp(self, event_number):
        """Calculate timestamp for event based on event number."""
        return self.base_time + int((event_number * self.inter_event_delay_us) / 1000)
    
    def generate_event_by_id(self, event_id):
        """Generate event based on event ID - core deterministic logic."""
        # Determine event type based on ID
        rem = event_id % TOTAL_PROPORTION
        
        timestamp = self.get_event_timestamp(self.event_count)
        self.event_count += 1
        
        if rem < PERSON_PROPORTION:
            return self.generate_person(event_id, timestamp)
        elif rem < PERSON_PROPORTION + AUCTION_PROPORTION:
            return self.generate_auction(event_id, timestamp)
        else:
            return self.generate_bid(event_id, timestamp)
    
    def generate_person(self, event_id, timestamp):
        """Generate person event - deterministic based on event_id."""
        rng = random.Random(event_id)
        
        # Generate person ID - use modulo to keep cardinality bounded
        person_id = FIRST_PERSON_ID + (hash_id(event_id) % NUM_PEOPLE_CARDINALITY)
        
        # Generate name
        first_name = FIRST_NAMES[rng.randint(0, len(FIRST_NAMES) - 1)]
        last_name = LAST_NAMES[rng.randint(0, len(LAST_NAMES) - 1)]
        name = f"{first_name} {last_name}"
        
        # Email based on name
        email = f"{first_name.lower()}{last_name.lower()}@{rng.choice(['gmail.com', 'yahoo.com', 'hotmail.com'])}"
        
        # Location - 10% chance of being in Australia
        if rng.random() < 0.9:
            city_idx = rng.randint(0, len(US_CITIES) - 1)
            city = US_CITIES[city_idx]
            state = US_STATES[city_idx]
        else:
            city_idx = rng.randint(0, len(AU_CITIES) - 1)
            city = AU_CITIES[city_idx]
            state = AU_STATES[city_idx]
        
        # Credit card
        credit_card = f"{rng.randint(1000, 9999)}{rng.randint(1000, 9999)}{rng.randint(1000, 9999)}{rng.randint(1000, 9999)}"
        
        # Extra data
        extra = next_string(event_id, 50)
        
        return {
            "id": person_id,
            "name": name,
            "email_address": email,
            "credit_card": credit_card,
            "city": city,
            "state": state,
            "date_time": format_timestamp(timestamp, self.use_iso),
            "extra": extra
        }
    
    def last_base0_person_id(self, event_id):
        """Get the last person ID that could have been generated."""
        # Find the last person event before this one
        person_event_id = event_id
        while person_event_id % TOTAL_PROPORTION >= PERSON_PROPORTION:
            person_event_id -= 1
        return hash_id(person_event_id) % NUM_PEOPLE_CARDINALITY
    
    def generate_auction(self, event_id, timestamp):
        """Generate auction event - deterministic based on event_id."""
        rng = random.Random(event_id)
        
        # Generate auction ID
        auction_id = FIRST_AUCTION_ID + (hash_id(event_id) % NUM_AUCTIONS_CARDINALITY)
        
        # Seller ID - hot sellers get more auctions
        if rng.randint(0, HOT_SELLER_RATIO - 1) > 0:
            # 99% chance - normal seller
            seller = FIRST_PERSON_ID + rng.randint(0, NUM_ACTIVE_PEOPLE - 1)
        else:
            # 1% chance - hot seller (choose from first few sellers)
            seller = FIRST_PERSON_ID + (self.last_base0_person_id(event_id) / HOT_SELLER_RATIO) * HOT_SELLER_RATIO
        
        # Category
        category = FIRST_CATEGORY_ID + rng.randint(0, NUM_CATEGORIES - 1)
        
        # Item name and description
        item_name = f"item-{rng.randint(0, 1000)}"
        description = f"Description for {item_name}: " + next_string(event_id, 100)
        
        # Prices
        initial_bid = rng.randint(100, 10000)
        reserve = initial_bid + rng.randint(100, 10000)
        
        # Auction runs for 1-7 days
        expires = timestamp + rng.randint(1, 7) * 24 * 60 * 60 * 1000
        
        # Extra data
        extra = next_string(event_id, 50)
        
        return {
            "id": auction_id,
            "item_name": item_name,
            "description": description,
            "initial_bid": initial_bid,
            "reserve": reserve,
            "date_time": format_timestamp(timestamp, self.use_iso),
            "expires": format_timestamp(expires, self.use_iso),
            "seller": seller,
            "category": category,
            "extra": extra
        }
    
    def last_base0_auction_id(self, event_id):
        """Get the last auction ID that could have been generated."""
        # Find the last auction event before this one
        auction_event_id = event_id
        while True:
            rem = auction_event_id % TOTAL_PROPORTION
            if PERSON_PROPORTION <= rem < PERSON_PROPORTION + AUCTION_PROPORTION:
                break
            auction_event_id -= 1
            if auction_event_id < 0:
                return 0
        return hash_id(auction_event_id) % NUM_AUCTIONS_CARDINALITY
    
    def generate_bid(self, event_id, timestamp):
        """Generate bid event - deterministic based on event_id."""
        rng = random.Random(event_id)
        
        # Auction ID - hot auctions get more bids
        if rng.randint(0, HOT_AUCTION_RATIO - 1) > 0:
            # 99% chance - normal auction
            # Choose from recent auctions
            last_auction = self.last_base0_auction_id(event_id)
            if last_auction > 0:
                auction = FIRST_AUCTION_ID + rng.randint(
                    max(0, last_auction - NUM_IN_FLIGHT_AUCTIONS), 
                    last_auction
                )
            else:
                auction = FIRST_AUCTION_ID
        else:
            # 1% chance - hot auction
            auction = FIRST_AUCTION_ID + (self.last_base0_auction_id(event_id) / HOT_AUCTION_RATIO) * HOT_AUCTION_RATIO
        
        # Bidder ID - hot bidders bid more
        if rng.randint(0, HOT_BIDDER_RATIO - 1) > 0:
            # 99% chance - normal bidder
            bidder = FIRST_PERSON_ID + rng.randint(0, NUM_ACTIVE_PEOPLE - 1)
        else:
            # 1% chance - hot bidder
            bidder = FIRST_PERSON_ID + ((self.last_base0_person_id(event_id) / HOT_BIDDER_RATIO) * HOT_BIDDER_RATIO + 1)
        
        # Price - exponential distribution
        price = int(100 * (1 + rng.expovariate(0.1)))
        
        # Channel
        if rng.randint(0, HOT_CHANNELS_RATIO - 1) > 0:
            # Use hot channel
            channel = rng.choice(HOT_CHANNELS)
            url = f"https://{channel.lower()}.com"
        else:
            # Regular channel
            channel_idx = rng.randint(1000, 10000)
            channel = f"channel-{channel_idx}"
            url = f"https://channel{channel_idx}.com"
        
        # Extra data
        extra = next_string(event_id, 50)
        
        return {
            "auction": auction,
            "bidder": bidder,
            "price": price,
            "channel": channel,
            "url": url,
            "date_time": format_timestamp(timestamp, self.use_iso),
            "extra": extra
        }
    
    def determine_topic(self, event):
        """Determine Kafka topic based on event fields."""
        if "email_address" in event:
            return "nexmark-person"
        elif "reserve" in event:
            return "nexmark-auction"
        elif "price" in event and "auction" in event:
            return "nexmark-bid"
        else:
            raise ValueError(f"Unknown event type: {event}")

def worker(worker_id, bootstrap_servers, events_per_second, max_events=None, use_iso=False, use_berlin_time=False):
    """Worker process that generates and sends events to Kafka."""
    print(f"Worker {worker_id} starting with {events_per_second} events/sec")
    
    # Initialize generator with offset for this worker
    generator = NexmarkGenerator(
        events_per_second=events_per_second,
        first_event_id=worker_id * 1000000,  # Each worker gets different ID space
        use_iso=use_iso,
        use_berlin_time=use_berlin_time
    )
    
    # Initialize Kafka producer
    config = {
        'bootstrap.servers': bootstrap_servers,
        'linger.ms': 10,
        'compression.type': 'lz4',
        'batch.size': 16384,
    }
    
    producer = Producer(config)
    
    event_id = generator.first_event_id
    events_sent = 0
    start_time = time.time()
    last_report_time = start_time
    
    topic_counts = {"nexmark-person": 0, "nexmark-auction": 0, "nexmark-bid": 0}
    
    try:
        while True:
            if max_events and events_sent >= max_events:
                break
            
            # Generate event
            event = generator.generate_event_by_id(event_id)
            topic = generator.determine_topic(event)
            
            # Send to Kafka
            producer.produce(
                topic=topic,
                value=json.dumps(event).encode('utf-8'),
                key=str(event["id"] if "id" in event else event.get("auction", "")).encode('utf-8')
            )
            
            event_id += 1
            events_sent += 1
            topic_counts[topic] += 1
            
            # Poll periodically
            if events_sent % 1000 == 0:
                producer.poll(0)
            
            # Report progress
            current_time = time.time()
            if current_time - last_report_time >= 1.0:
                elapsed = current_time - last_report_time
                rate = (events_sent - (last_report_time - start_time) * events_per_second) / elapsed
                
                print(f"Worker {worker_id}: {rate:.0f} events/sec, "
                      f"P:{topic_counts['nexmark-person']}, "
                      f"A:{topic_counts['nexmark-auction']}, "
                      f"B:{topic_counts['nexmark-bid']}")
                
                last_report_time = current_time
            
            # Rate limiting - sleep if ahead of schedule
            expected_events = int((time.time() - start_time) * events_per_second)
            if events_sent > expected_events:
                sleep_time = (events_sent - expected_events) / events_per_second
                if sleep_time > 0.001:
                    time.sleep(sleep_time)
    
    except KeyboardInterrupt:
        pass
    finally:
        producer.flush()
        print(f"Worker {worker_id} sent {events_sent} events")

def main():
    """Main entry point."""
    # Parse arguments - first try environment variables, then command line args
    bootstrap_servers = os.getenv('KAFKA_BROKER', '192.168.2.70:9094')
    events_per_second = int(os.getenv('EVENTS_PER_SECOND', 10000))
    num_workers = 1
    total_events_env = os.getenv('TOTAL_EVENTS')
    max_events = int(total_events_env) if total_events_env else None
    use_iso = False
    use_berlin_time = False
    
    # Check for --iso flag
    if '--iso' in sys.argv:
        use_iso = True
        sys.argv.remove('--iso')
    
    # Check for --berlin-time flag
    if '--berlin-time' in sys.argv:
        use_berlin_time = True
        sys.argv.remove('--berlin-time')
    
    if len(sys.argv) > 1:
        bootstrap_servers = sys.argv[1]
    if len(sys.argv) > 2:
        events_per_second = int(sys.argv[2])
    if len(sys.argv) > 3:
        num_workers = int(sys.argv[3])
    if len(sys.argv) > 4:
        max_events = int(sys.argv[4])
    
    # Show timezone info
    import time as time_module
    tz_name = time_module.tzname[time_module.daylight]
    offset_hours = -time_module.altzone / 3600 if time_module.daylight else -time_module.timezone / 3600
    
    print(f"Starting Nexmark generator:")
    print(f"  Kafka brokers: {bootstrap_servers}")
    print(f"  Target rate: {events_per_second} events/sec")
    print(f"  Workers: {num_workers}")
    print(f"  Max events: {max_events if max_events else 'unlimited'}")
    print(f"  Timezone: {tz_name} (UTC{offset_hours:+g})")
    print(f"  Timestamp format: {'ISO 8601 (local time)' if use_iso else 'Numeric (milliseconds)'}")
    if use_berlin_time:
        print(f"  Timestamp timezone: Berlin time (UTC+2)")
    print(f"  Event proportions - Person:{PERSON_PROPORTION}, Auction:{AUCTION_PROPORTION}, Bid:{BID_PROPORTION}")
    
    # Start workers
    processes = []
    events_per_worker = events_per_second // num_workers
    
    for i in range(num_workers):
        p = multiprocessing.Process(
            target=worker,
            args=(i, bootstrap_servers, events_per_worker, max_events // num_workers if max_events else None, use_iso, use_berlin_time)
        )
        processes.append(p)
        p.start()
    
    try:
        for p in processes:
            p.join()
    except KeyboardInterrupt:
        print("\nShutting down...")
        for p in processes:
            p.terminate()
        for p in processes:
            p.join()

if __name__ == "__main__":
    main()