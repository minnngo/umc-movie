package com.umc.movie.auth;

import com.umc.movie.exception.ErrorCode;
import com.umc.movie.exception.GeneralException;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * Access Token을 만들고 검증합니다.
 * 토큰 = Header.Payload.Signature 이고, Payload의 subject에 memberId를 담습니다.
 * Signature는 서버만 아는 secret으로 만들기 때문에, 누가 Payload의 memberId를 바꾸면 서명 검증에서 걸립니다.
 */
@Component
public class JwtProvider {

    private final SecretKey key;
    private final long accessExpirationSeconds;

    public JwtProvider(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.access-expiration}") long accessExpirationSeconds
    ) {
        // HS256 서명 키는 32바이트 이상이어야 합니다. 짧으면 서버 시작 시 오류가 납니다.
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessExpirationSeconds = accessExpirationSeconds;
    }

    public String createAccessToken(Long memberId) {
        Date now = new Date();
        return Jwts.builder()
                .subject(String.valueOf(memberId))
                .issuedAt(now)
                .expiration(new Date(now.getTime() + accessExpirationSeconds * 1000))
                .signWith(key)
                .compact();
    }

    /** 서명과 만료 시간을 검증한 뒤 토큰 주인의 memberId를 돌려줍니다. */
    public Long getMemberId(String token) {
        try {
            String subject = Jwts.parser()
                    .verifyWith(key)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload()
                    .getSubject();
            return Long.valueOf(subject);
        } catch (ExpiredJwtException e) {
            throw new GeneralException(ErrorCode.TOKEN_EXPIRED);
        } catch (JwtException | IllegalArgumentException e) {
            throw new GeneralException(ErrorCode.TOKEN_INVALID);
        }
    }
}
