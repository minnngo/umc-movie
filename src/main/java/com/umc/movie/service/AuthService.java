package com.umc.movie.service;

import com.umc.movie.auth.JwtProvider;
import com.umc.movie.dto.LoginRequest;
import com.umc.movie.dto.LoginResponse;
import com.umc.movie.entity.Member;
import com.umc.movie.exception.ErrorCode;
import com.umc.movie.exception.GeneralException;
import com.umc.movie.repository.MemberRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final MemberRepository memberRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtProvider jwtProvider;

    @Transactional(readOnly = true)
    public LoginResponse login(LoginRequest request) {
        Member member = memberRepository.findByEmail(request.email())
                .orElseThrow(() -> new GeneralException(ErrorCode.LOGIN_FAILED));

        // 저장된 bcrypt 해시와 입력한 평문 비밀번호를 비교합니다. 해시를 풀어서 비교하는 게 아닙니다.
        if (!passwordEncoder.matches(request.password(), member.getPassword())) {
            throw new GeneralException(ErrorCode.LOGIN_FAILED);
        }

        String accessToken = jwtProvider.createAccessToken(member.getMemberId());
        return new LoginResponse(member.getNickname(), accessToken);
    }
}
