package com.umc.movie.controller;

import com.umc.movie.dto.ApiResponse;
import com.umc.movie.exception.ErrorCode;
import com.umc.movie.exception.GeneralException;
import org.hibernate.exception.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

@RestControllerAdvice
public class GlobalExceptionHandler {
    // MySQL 메시지 예) Duplicate entry 'umc@example.com' for key 'member.email'
    private static final Pattern DUPLICATE_KEY = Pattern.compile("for key '([^']+)'");

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidation(MethodArgumentNotValidException exception) {
        String message = exception.getBindingResult().getFieldErrors().get(0).getDefaultMessage();
        return ResponseEntity.badRequest().body(ApiResponse.failure("COMMON4001", message));
    }

    @ExceptionHandler(GeneralException.class)
    public ResponseEntity<ApiResponse<Void>> handleGeneral(GeneralException exception) {
        return toResponse(exception.getErrorCode());
    }

    /**
     * 서비스의 사전 중복 체크를 통과했어도, 같은 값으로 거의 동시에 들어온 요청은
     * DB UNIQUE 제약에서 막힙니다. 어떤 제약이 위반됐는지 보고 사전 체크와 같은 code로 응답합니다.
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleDataIntegrity(DataIntegrityViolationException exception) {
        String constraint = findConstraintName(exception);
        if (constraint.contains("email")) {
            return toResponse(ErrorCode.MEMBER_EMAIL_DUPLICATED);
        }
        if (constraint.contains("nickname")) {
            return toResponse(ErrorCode.MEMBER_NICKNAME_DUPLICATED);
        }
        return ResponseEntity.status(409).body(ApiResponse.failure("COMMON4091", "이미 존재하는 데이터입니다."));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<Void>> handleIllegalArgument(IllegalArgumentException exception) {
        return ResponseEntity.status(409).body(ApiResponse.failure("COMMON4092", exception.getMessage()));
    }

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<ApiResponse<Void>> handleResponseStatus(ResponseStatusException exception) {
        int status = exception.getStatusCode().value();
        return ResponseEntity.status(status)
                .body(ApiResponse.failure("COMMON" + status, exception.getReason()));
    }

    private ResponseEntity<ApiResponse<Void>> toResponse(ErrorCode errorCode) {
        return ResponseEntity.status(errorCode.getStatus())
                .body(ApiResponse.failure(errorCode.getCode(), errorCode.getMessage()));
    }

    /** Hibernate가 알려주는 제약 이름을 먼저 쓰고, 없으면 DB 메시지의 key 이름을 꺼냅니다. */
    private String findConstraintName(DataIntegrityViolationException exception) {
        if (exception.getCause() instanceof ConstraintViolationException violation
                && violation.getConstraintName() != null) {
            return violation.getConstraintName().toLowerCase();
        }
        Matcher matcher = DUPLICATE_KEY.matcher(String.valueOf(exception.getMostSpecificCause().getMessage()));
        return matcher.find() ? matcher.group(1).toLowerCase() : "";
    }
}
