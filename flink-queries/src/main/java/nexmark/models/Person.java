package nexmark.models;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Person {
    @JsonProperty("id")
    private long id;
    
    @JsonProperty("name")
    private String name;
    
    @JsonProperty("email_address")
    private String emailAddress;
    
    @JsonProperty("credit_card")
    private String creditCard;
    
    @JsonProperty("city")
    private String city;
    
    @JsonProperty("state")
    private String state;
    
    @JsonProperty("date_time")
    private long dateTime;
    
    @JsonProperty("extra")
    private String extra;

    public Person() {}

    public Person(long id, String name, String emailAddress, String creditCard, 
                  String city, String state, long dateTime, String extra) {
        this.id = id;
        this.name = name;
        this.emailAddress = emailAddress;
        this.creditCard = creditCard;
        this.city = city;
        this.state = state;
        this.dateTime = dateTime;
        this.extra = extra;
    }

    public long getId() { return id; }
    public void setId(long id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getEmailAddress() { return emailAddress; }
    public void setEmailAddress(String emailAddress) { this.emailAddress = emailAddress; }

    public String getCreditCard() { return creditCard; }
    public void setCreditCard(String creditCard) { this.creditCard = creditCard; }

    public String getCity() { return city; }
    public void setCity(String city) { this.city = city; }

    public String getState() { return state; }
    public void setState(String state) { this.state = state; }

    public long getDateTime() { return dateTime; }
    public void setDateTime(long dateTime) { this.dateTime = dateTime; }

    public String getExtra() { return extra; }
    public void setExtra(String extra) { this.extra = extra; }

    @Override
    public String toString() {
        return "Person{" +
                "id=" + id +
                ", name='" + name + '\'' +
                ", emailAddress='" + emailAddress + '\'' +
                ", city='" + city + '\'' +
                ", state='" + state + '\'' +
                ", dateTime=" + dateTime +
                '}';
    }
}