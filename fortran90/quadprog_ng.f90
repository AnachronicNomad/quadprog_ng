module quadprog_ng
  implicit none
contains
  subroutine solve_qp(quadr_coeff_G, linear_coeff_a,
                      n_ineq, ineq_coef_C, ineq_vec_d,
                      m_eq, eq_coef_A, eq_vec_b,
                      nvars, sol, ierr)
    !
    implicit none

    !!
    !! Externals
    !! 

    ! quadratic coefficient matrix G in 
    ! 
    real(8), allocatable, intent(in) :: quadr_coeff_G(:,:)
    real(8), allocatable, intent(in) :: linear_coeff_a(:)
    
    integer, intent(in) :: n_ineq
    real(8), allocatable, intent(in) :: ineq_coef_C(:,:)
    real(8), allocatable, intent(in) :: ineq_vec_d(:)

    integer, intent(in) :: m_eq
    real(8), allocatable, intent(in) :: eq_coef_A
    real(8), allocatable, intent(in) :: eq_vec_b

    integer, intent(in) :: nvars

    ! the solution iterate
    real(8), allocatable, intent(inout) :: sol(:)

    ! If ierr is set to anything except for zero, a problem happened
    integer, intent(inout) :: ierr = 0    

    !!
    !! Internals
    !!
    logical DONE = .FALSE.
    logical FULL_STEP = .FALSE. 
    logical ADDING_EQ_CONSTRAINTS = .TRUE.

    logical first_pass = .TRUE. 

    integer status = 0
    integer irow, icol = 1

    real(8), allocatable :: G_inv(:,:)
    real(8), allocatable :: U_work(:,:)

    !! Cholesky decomp of quadr_coeff_G
    real(8), allocatable :: chol_L(:,:)
    real(8), allocatable :: inv_chol_L(:,:)

    !! QR factorization of B = L^{-1} N
    real(8), allocatable :: Q(:,:)
    real(8), allocatable :: R(:,:)

    !! J = L^{-T} Q, inverse transpose of L by columns of Q = [Q1 | Q2]
    !! Q1 has the columns corresponding to active constraints 
    real(8), allocatable :: J1(:,:)
    real(8), allocatable :: J2(:,:)

    integer, allocatable :: active_set(:)
    integer, allocatable :: n_p(:)
    integer :: p, &
               q 

    real(8), allocatable :: u(:)
    real(8), allocatable :: lagr(:)

    integer :: k_dropped, &
               j_dropped

    real(8), allocatable :: z(:), & 
                            r(:)

    !!~~~ Allocations & Initializations ~~~!!
    if (m_eq .eq. 0) then
      ADDING_EQ_CONSTRAINTS = .true.
    else
      ADDING_EQ_CONSTRAINTS = .false. 
    endif

    if (.not. (allocated(sol))) then
      allocate(sol(nvars))
    endif

    allocate(chol_L(nvars, nvars))
    allocate(inv_chol_L(nvars, nvars))

    !! Begin chol factorization and use the factors to get
    !! the inverse of the matrix G

    ! Lower triangular cholesky 
    call dpotrf('L', nvars, L, nvars, status)

    ! Set all non-lower-triangular entries to 0
    do icol=1,nvars
        do irow=1,nvars
            if (irow .lt. icol) then
                L(irow, icol) = 0
            endif
        enddo
    enddo

    allocate(G_inv(nvars,nvars))

    G_inv = L

    ! calc G^{-1}
    call dpotri('L', nvars, G_inv, nvars, status)

    allocate(U_work(nvars,nvars))

    U_work = G

    call dpotrf('U', 4, U_work, 4, info)
    call dpotri('U', 4, U_work, 4, info)

    do icol=1,nvars
        do irow=1,nvars
            if (irow .ge. icol) then
                U_work(irow, icol) = 0
            endif
        enddo
    enddo

    !! Begin adding the lower and upper terms

    do icol=1,nvars
      do irow=1,nvars
        G_inv(irow, icol) = G_inv(irow,icol) + U_work(irow,icol)
      enddo
    enddo
    


    !!~~~ Begin Processing ~~~!!
    !! Solution iterate


  end subroutine solve_qp
end module


program test

end program test