package com.umc.movie.auth;

import com.umc.movie.exception.ErrorCode;
import com.umc.movie.exception.GeneralException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.cors.CorsUtils;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * 로그인이 필요한 API 요청을 Controller보다 먼저 가로채 토큰을 검증합니다.
 * 검증에 성공하면 토큰 속 memberId를 요청에 담아 두고, Controller는 @LoginMember로 꺼내 씁니다.
 * 여기서 던진 예외도 GlobalExceptionHandler가 같은 형식(401)으로 응답합니다.
 */
@Component
@RequiredArgsConstructor
public class AuthInterceptor implements HandlerInterceptor {

    public static final String MEMBER_ID_ATTRIBUTE = "loginMemberId";
    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtProvider jwtProvider;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // 브라우저가 본 요청 전에 보내는 CORS 사전 요청(OPTIONS)에는 토큰이 없으므로 통과시킵니다.
        if (CorsUtils.isPreFlightRequest(request)) {
            return true;
        }

        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.startsWith(BEARER_PREFIX)) {
            throw new GeneralException(ErrorCode.TOKEN_MISSING);
        }

        String token = header.substring(BEARER_PREFIX.length());
        request.setAttribute(MEMBER_ID_ATTRIBUTE, jwtProvider.getMemberId(token));
        return true;
    }
}
