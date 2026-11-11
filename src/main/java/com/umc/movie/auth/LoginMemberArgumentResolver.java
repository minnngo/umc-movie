package com.umc.movie.auth;

import com.umc.movie.exception.ErrorCode;
import com.umc.movie.exception.GeneralException;
import org.springframework.core.MethodParameter;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

/** AuthInterceptor가 요청에 담아 둔 memberId를 @LoginMember Long 파라미터로 넣어줍니다. */
@Component
public class LoginMemberArgumentResolver implements HandlerMethodArgumentResolver {

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(LoginMember.class)
                && parameter.getParameterType().equals(Long.class);
    }

    @Override
    public Object resolveArgument(
            MethodParameter parameter,
            ModelAndViewContainer mavContainer,
            NativeWebRequest webRequest,
            WebDataBinderFactory binderFactory
    ) {
        Object memberId = webRequest.getAttribute(AuthInterceptor.MEMBER_ID_ATTRIBUTE, RequestAttributes.SCOPE_REQUEST);
        // 인터셉터 경로에 등록하지 않은 API에서 @LoginMember를 쓰면 여기서 막힙니다.
        if (memberId == null) {
            throw new GeneralException(ErrorCode.TOKEN_MISSING);
        }
        return memberId;
    }
}
