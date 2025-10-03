package nexmark.models;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Auction {
    @JsonProperty("id")
    private long id;
    
    @JsonProperty("item_name")
    private String itemName;
    
    @JsonProperty("description")
    private String description;
    
    @JsonProperty("initial_bid")
    private long initialBid;
    
    @JsonProperty("reserve")
    private long reserve;
    
    @JsonProperty("date_time")
    private long dateTime;
    
    @JsonProperty("expires")
    private long expires;
    
    @JsonProperty("seller")
    private long seller;
    
    @JsonProperty("category")
    private int category;
    
    @JsonProperty("extra")
    private String extra;

    public Auction() {}

    public Auction(long id, String itemName, String description, long initialBid, 
                   long reserve, long dateTime, long expires, long seller, 
                   int category, String extra) {
        this.id = id;
        this.itemName = itemName;
        this.description = description;
        this.initialBid = initialBid;
        this.reserve = reserve;
        this.dateTime = dateTime;
        this.expires = expires;
        this.seller = seller;
        this.category = category;
        this.extra = extra;
    }

    public long getId() { return id; }
    public void setId(long id) { this.id = id; }

    public String getItemName() { return itemName; }
    public void setItemName(String itemName) { this.itemName = itemName; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public long getInitialBid() { return initialBid; }
    public void setInitialBid(long initialBid) { this.initialBid = initialBid; }

    public long getReserve() { return reserve; }
    public void setReserve(long reserve) { this.reserve = reserve; }

    public long getDateTime() { return dateTime; }
    public void setDateTime(long dateTime) { this.dateTime = dateTime; }

    public long getExpires() { return expires; }
    public void setExpires(long expires) { this.expires = expires; }

    public long getSeller() { return seller; }
    public void setSeller(long seller) { this.seller = seller; }

    public int getCategory() { return category; }
    public void setCategory(int category) { this.category = category; }

    public String getExtra() { return extra; }
    public void setExtra(String extra) { this.extra = extra; }

    @Override
    public String toString() {
        return "Auction{" +
                "id=" + id +
                ", itemName='" + itemName + '\'' +
                ", initialBid=" + initialBid +
                ", reserve=" + reserve +
                ", dateTime=" + dateTime +
                ", expires=" + expires +
                ", seller=" + seller +
                ", category=" + category +
                '}';
    }
}