package nexmark.models;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;

public class PersonDeserializerFlink implements DeserializationSchema<Person> {
    private static final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public Person deserialize(byte[] message) {
        try {
            return objectMapper.readValue(message, Person.class);
        } catch (Exception e) {
            System.err.println("Failed to deserialize person: " + e.getMessage());
            return null;
        }
    }

    @Override
    public boolean isEndOfStream(Person nextElement) {
        return false;
    }

    @Override
    public TypeInformation<Person> getProducedType() {
        return TypeInformation.of(Person.class);
    }
}