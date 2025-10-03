package nexmark.models;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;

public class AuctionDeserializerFlink implements DeserializationSchema<Auction> {
    private static final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public Auction deserialize(byte[] message) {
        try {
            return objectMapper.readValue(message, Auction.class);
        } catch (Exception e) {
            System.err.println("Failed to deserialize auction: " + e.getMessage());
            return null;
        }
    }

    @Override
    public boolean isEndOfStream(Auction nextElement) {
        return false;
    }

    @Override
    public TypeInformation<Auction> getProducedType() {
        return TypeInformation.of(Auction.class);
    }
}