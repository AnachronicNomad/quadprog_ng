module quadprog_ng_redo
  implicit none
contains
  subroutine do_cholesky_and_inverse(rank_A, in_mat_A, out_mat_L, out_mat_Inv)
    implicit none
    integer, intent(in) :: rank_A
    real(8), allocatable, intent(in) :: in_mat_A(:,:)
    real(8), allocatable, intent(out) :: out_mat_L(:,:), out_mat_Inv(:,:)

    integer :: irow, icol = 0
    real(8), allocatable :: mat_U(:,:)

    integer :: ierr

    allocate(mat_U(rank_A, rank_A))

    if (.not. allocated(out_mat_L)) then
      allocate(out_mat_L(rank_A, rank_A))
      out_mat_L = 0
    endif

    if (.not. allocated(out_mat_Inv)) then
      allocate(out_mat_Inv(rank_A, rank_A))
      out_mat_Inv = 0
    endif

    out_mat_L = in_mat_A
    mat_U = in_mat_A

    call dpotrf('L', rank_A, out_mat_L, rank_A, ierr)
    call dpotrf('U', rank_A, mat_U, rank_A, ierr)

    out_mat_Inv = out_mat_L

    call dpotri('L', rank_A, out_mat_Inv, rank_A, ierr)
    call dpotri('U', rank_A, mat_U, rank_A, ierr)

    !! Zero out bad entries in upper and lower
    do icol=1,rank_A
        do irow=1,rank_A
            if (irow .lt. icol) then
                out_mat_Inv(irow, icol) = 0
                out_mat_L(irow, icol) = 0
            endif
        enddo
    enddo

    do icol=1,rank_A
        do irow=1,rank_A
            if (irow .ge. icol) then
                mat_U(irow, icol) = 0
            endif
        enddo
    enddo

    out_mat_Inv = out_mat_Inv + mat_U

    return
  end subroutine

  subroutine get_inverse(rank_A, in_mat_A, out_mat_A_Inv)
    implicit none
    integer, intent(in) :: rank_A
    real(8), allocatable, intent(in) :: in_mat_A(:,:)
    real(8), allocatable, intent(out) :: out_mat_A_Inv(:,:)

    integer, allocatable :: ipiv(:)
    real(8), allocatable :: work(:)

    integer :: ierr
    integer :: lwork

    allocate(ipiv(rank_A))

    if (.not. allocated(out_mat_A_Inv)) then
      allocate(out_mat_A_Inv(rank_A, rank_A))
    endif

    out_mat_A_Inv = 0
    out_mat_A_Inv(1:rank_A, 1:rank_A) = in_mat_A(1:rank_A, 1:rank_A)

    call dgetrf(rank_A, rank_A, out_mat_A_Inv, rank_A, ipiv, ierr)

    lwork = 32 * rank_A
    allocate(work(lwork))

    call dgetri(rank_A, out_mat_A_Inv, rank_A, ipiv, work, lwork, ierr)

    deallocate(ipiv)
    deallocate(work)
  end subroutine

  subroutine get_qr(nrow, ncol, in_mat_A, mat_Q, mat_R)
    implicit none
    integer, intent(in) :: nrow, ncol
    real(8), allocatable, intent(in) :: in_mat_A(:,:)
    real(8), allocatable, intent(out) :: mat_Q(:,:), mat_R(:,:)

    real(8), allocatable :: work(:), tau(:), temp(:), temp_R(:,:)
    integer :: lwork, ierr, irow, icol

    allocate(tau(min(nrow, ncol)))
    tau = 0
    allocate(temp(1))
    temp = 0

    print *, "doing allocations"

    if (.not. allocated(mat_Q)) then
      allocate(mat_Q(nrow, nrow))
      mat_Q = 0
    endif

    print *, "allocated q"

    if (.not. allocated(mat_R)) then
      allocate(mat_R(nrow, ncol))
      mat_R = 0
    endif

    print *, "allocated r"

    mat_R = 0
    mat_R(1:nrow, 1:ncol) = in_mat_A(1:nrow, 1:ncol)

    !! Do a dummy call to find optimal lwork value
    call dgeqrf(nrow, ncol, mat_R, nrow, tau, temp, -1, ierr)

    lwork = int(temp(1))
    allocate(work(lwork))

    print *, "starting R"

    !! Form R
    call dgeqrf(nrow, ncol, mat_R, nrow, tau, work, lwork, ierr)

    print *, "doing temp move"

    allocate(temp_R(nrow, max(nrow, ncol)))
    temp_R = 0
    temp_R(1:nrow,1:ncol) = mat_R(1:nrow, 1:ncol)

    print *, "start Q"

    !! Get Q back from it
    call dorgqr(nrow, nrow, nrow, temp_R, nrow, tau, work, lwork, ierr)

    mat_Q = 0
    mat_Q(1:nrow, 1:ncol) = temp_R(1:nrow, 1:nrow)

    print *, "done Q"

    !! zero out bad entries to make R upper triangular
    do icol=1,ncol
        do irow=1,nrow
            if (irow .gt. icol) then
                mat_R(irow, icol) = 0
            endif
        enddo
    enddo

    deallocate(temp_R)
    deallocate(work)
    deallocate(tau)
    deallocate(temp)
  end subroutine


  subroutine solve_qp(quadr_coeff_G, linear_coeff_a, &
                      n_ineq, ineq_coef_C, ineq_vec_d, &
                      m_eq, eq_coef_A, eq_vec_b, &
                      nvars, sol, ierr)
    !
    implicit none

    !!
    !! Externals
    !! 

    ! quadratic coefficient matrix G in 
    real(8), allocatable, intent(in) :: quadr_coeff_G(:,:)
    real(8), allocatable, intent(in) :: linear_coeff_a(:)
    
    integer, intent(in) :: n_ineq
    real(8), allocatable, intent(in) :: ineq_coef_C(:,:)
    real(8), allocatable, intent(in) :: ineq_vec_d(:)

    integer, intent(in) :: m_eq
    real(8), allocatable, intent(in) :: eq_coef_A(:,:)
    real(8), allocatable, intent(in) :: eq_vec_b(:)

    integer, intent(in) :: nvars
    integer, intent(inout) :: ierr

    ! the solution iterate
    real(8), allocatable, intent(inout) :: sol(:)

    !!~~~~~~~~~~ Internals ~~~~~~~~~~!!
    logical :: DONE, FULL_STEP = .false.
    logical :: FIRST_PASS = .true. 

    integer :: irow, icol
    integer :: p,q = 0

    real(8), allocatable :: ineq_prb(:)
    real(8), allocatable :: n_p(:)
    real(8), allocatable :: u(:), lagr(:)

    real(8), allocatable :: G_inv(:,:)
    real(8), allocatable :: L_chol(:,:), L_inv(:,:)

    real(8), allocatable :: matB(:,:), matJ(:,:), matQ(:,:), matR(:,:)

    real(8), allocatable :: z_step(:), r_step(:)

    real(8) :: t, t1, t2
    real(8) :: MAX_DOUBLE = huge(t)

    integer :: k, k_dropped, j_dropped
    integer, allocatable :: active_set(:)

    !!~~~~~~~~ Allocations ~~~~~~~~!!
    allocate(L_chol(nvars,nvars))
    allocate(L_inv(nvars,nvars))
    allocate(G_inv(nvars,nvars))
    
    call do_cholesky_and_inverse(nvars, quadr_coeff_G, L_chol, G_inv)
    call get_inverse(nvars, L_chol, L_inv)

    sol = (-1) * matmul(G_inv, linear_coeff_a)

    allocate(ineq_prb(nvars))
    allocate(n_p(nvars))

    allocate(u(n_ineq))
    allocate(lagr(n_ineq))

    allocate(z_step(nvars))
    allocate(r_step(n_ineq))

    allocate(matQ(nvars, nvars))
    allocate(matJ(nvars, nvars))

    allocate(matB(nvars, n_ineq))    
    allocate(matR(nvars, n_ineq))
    allocate(Rinv(nvars, n_ineq))

    allocate(active_set(n_ineq))
    active_set = 0

    do while (.not. DONE)
      ineq_prb = matmul(transpose(ineq_coef_C), sol) - ineq_vec_d

      if (any(ineq < 0)) then 
        do icol=1,nvars
          if (ineq(icol) .lt. 0) then
            p = icol
            exit
          endif
        enddo

        n_p = ineq_coef_C(:,p)

        if (q .eq. 0) then
          u = 0
        endif

        lagr = 0
        lagr(1:q) = u(1:q)

        FULL_STEP = .false.

        do while (.not. FULL_STEP) 
          ineq_prb = matmul(transpose(ineq_coef_C), sol) - ineq_vec_d

          !!###~~~~~~~~ Step 2(a) ~~~~~~~~###
          !!## Calculate step directions
          if (FIRST_PASS) then
            z_step = matmul(G_inv, n_p)
            FIRST_PASS = .false. 
          else
            z_step = matmul(matmul(J(:, q+1:), transpose(J(:, q+1:))), n_p)

            if (q .gt. 0) then
              Rinv = 0
              call get_inverse(q, matR, Rinv)

              r_step = 0
              r_step(1:q) = matmul(matmul(Rinv(1:q,1:q), transpose(J(:,1:q))), n_p)
            endif
          endif

          !!###~~~~~~~~ Step 2(b) ~~~~~~~~###
          !! partial step length t1 - max step in dual space          
          if ((q .eq. 0) .or. (all(r .le. 0))) then
            t1 = MAX_DOUBLE
          else
            t1 = MAX_DOUBLE
            k_dropped = 0

            do icol=1,q
              if ((r(icol) .gt. 0) .and. (lagr(icol) / r_step(icol) .lt. t1)) then
                t1 = lagr(icol) / r_step(icol)
                k_dropped = active_set(icol)
                j_dropped = icol
              endif
            enddo
          endif

          !! full step length t2 - min step in primal space
          if (all(z .eq. 0)) then
            t2 = MAX_DOUBLE
          else
            t2 = (-1) * ineq_prb(p) / dot_product(z_step, n_p)
          endif

          t = min(t1, t2)

          !!###~~~~~~~~ Step 2(c) ~~~~~~~~###
          if (t .eq. MAX_DOUBLE) then
            print *, "infeasible! stop here!"
            FULL_STEP = .true.
            DONE = .true. 
            ierr = 420
            return
          endif

          !! If t2 infinite, then a full step is infeasible
          if (t2 .eq. MAX_DOUBLE) then
            !update lagr

            !update active_set

            !update QR

            cycle
          endif

          sol = sol + (t * z)
          !update lagr

          if (t .eq. t2) then
            ! update active set

            ! update lagr

            ! update QR

            FULL_STEP = .true. 
            exit
          endif

          if (t .eq. t1) then
            ! update active set

            ! update QR
            cycle
          endif
        enddo

      else
        DONE = .true.
      endif

    enddo

    deallocate(L_chol)
    deallocate(L_inv)
    deallocate(G_inv)

    deallocate(ineq_prb)
    deallocate(n_p)

  end subroutine solve_qp
end module


program test
  use quadprog_ng_redo
  implicit none
  real(8), allocatable :: G(:,:), lin_vec(:), C(:,:), d(:), A(:,:), b(:), sol(:)
  integer :: irow, icol
  integer :: m_eq, n_ineq, ierr

  integer, dimension(2) :: mat_dim

  G = transpose(reshape((/4, -2, -2, 4/),(/2,2/)))

  lin_vec = (/6, 0/)

  C = transpose(reshape((/1, 0, 1, 0, 1, 1/),(/3,2/)))

  d = (/0, 0, 2/)

  allocate(A(1,1))
  A = 0

  allocate(b(1))
  b = 1

  m_eq = 0
  n_ineq = 3

  allocate(sol(2))

  call solve_qp(G, lin_vec, &
                      n_ineq, C, d, &
                      m_eq, A, b, &
                      2, sol, ierr)

  print *, sol

end program test