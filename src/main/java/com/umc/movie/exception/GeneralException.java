package com.umc.movie.exception;

import lombok.Getter;

// 서비스에서 ErrorCode를 담아 던지면 GlobalExceptionHandler가 같은 형식으로 응답합니다.
@Getter
public class GeneralException extends RuntimeException {
    private final ErrorCode errorCode;

    public GeneralException(ErrorCode errorCode) {
        super(errorCode.getMessage());
        this.errorCode = errorCode;
    }
}
