package com.umc.movie.service;

import com.umc.movie.dto.EmailCheckResponse;
import com.umc.movie.dto.MemberResponse;
import com.umc.movie.dto.MyInfoResponse;
import com.umc.movie.dto.NicknameCheckResponse;
import com.umc.movie.dto.SignUpRequest;
import com.umc.movie.dto.UpdateMyInfoRequest;
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
public class MemberService {

    private final MemberRepository memberRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional(readOnly = true)
    public NicknameCheckResponse checkNickname(String nickname) {
        boolean exists = memberRepository.existsByNickname(nickname);
        return new NicknameCheckResponse(!exists);
    }

    @Transactional(readOnly = true)
    public EmailCheckResponse checkEmail(String email) {
        boolean exists = memberRepository.existsByEmail(email);
        return new EmailCheckResponse(!exists);
    }

    @Transactional(readOnly = true)
    public MyInfoResponse getMyInfo(Long memberId) {
        return MyInfoResponse.from(findMember(memberId));
    }

    @Transactional
    public MyInfoResponse updateMyInfo(Long memberId, UpdateMyInfoRequest request) {
        Member member = findMember(memberId);

        // 지금 닉네임 그대로 보내면 중복이 아니므로 통과시킵니다.
        if (!member.getNickname().equals(request.nickname())
                && memberRepository.existsByNickname(request.nickname())) {
            throw new GeneralException(ErrorCode.MEMBER_NICKNAME_DUPLICATED);
        }

        // 트랜잭션 안에서 조회한 엔티티라 값만 바꾸면 끝날 때 UPDATE가 실행됩니다. (변경 감지)
        member.updateNickname(request.nickname());
        return MyInfoResponse.from(member);
    }

    private Member findMember(Long memberId) {
        return memberRepository.findById(memberId)
                .orElseThrow(() -> new GeneralException(ErrorCode.MEMBER_NOT_FOUND));
    }

    @Transactional
    public MemberResponse signUp(SignUpRequest request) {
        if (memberRepository.existsByEmail(request.email())) {
            throw new GeneralException(ErrorCode.MEMBER_EMAIL_DUPLICATED);
        }
        if (memberRepository.existsByNickname(request.nickname())) {
            throw new GeneralException(ErrorCode.MEMBER_NICKNAME_DUPLICATED);
        }

        Member member = Member.builder()
                .email(request.email())
                .password(passwordEncoder.encode(request.password()))
                .nickname(request.nickname())
                .build();

        Member savedMember = memberRepository.save(member);
        return new MemberResponse(savedMember.getMemberId(), savedMember.getEmail(), savedMember.getNickname());
    }
}
