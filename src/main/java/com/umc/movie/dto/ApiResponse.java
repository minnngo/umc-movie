package com.umc.movie.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;

// 성공과 실패를 같은 틀로 응답합니다. { isSuccess, code, message, result }
@JsonPropertyOrder({"isSuccess", "code", "message", "result"})
public record ApiResponse<T>(
        // record의 isSuccess()를 Jackson이 "success"로 읽지 않도록 이름을 고정합니다.
        @JsonProperty("isSuccess") boolean isSuccess,
        String code,
        String message,
        T result
) {
    public static <T> ApiResponse<T> created(String message, T result) {
        return new ApiResponse<>(true, "COMMON201", message, result);
    }
}
