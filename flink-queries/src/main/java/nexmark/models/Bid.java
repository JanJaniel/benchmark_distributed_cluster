package nexmark.models;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public class Bid {
    public long auction;
    public long bidder;
    public long price;
    
    @JsonProperty("date_time")
    public long dateTime;
    
    public String channel;
    public String url;
    public String extra;

    public Bid() {}

    public Bid(long auction, long bidder, long price, long dateTime, String extra) {
        this.auction = auction;
        this.bidder = bidder;
        this.price = price;
        this.dateTime = dateTime;
        this.extra = extra;
    }

    @Override
    public String toString() {
        return String.format("Bid{auction=%d, bidder=%d, price=%d, dateTime=%d}", 
                            auction, bidder, price, dateTime);
    }
}