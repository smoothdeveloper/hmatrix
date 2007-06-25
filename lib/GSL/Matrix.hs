-----------------------------------------------------------------------------
-- |
-- Module      :  GSL.Matrix
-- Copyright   :  (c) Alberto Ruiz 2007
-- License     :  GPL-style
--
-- Maintainer  :  Alberto Ruiz <aruiz@um.es>
-- Stability   :  provisional
-- Portability :  portable (uses FFI)
--
-- A few linear algebra computations based on the GSL (<http://www.gnu.org/software/gsl>).
--
-----------------------------------------------------------------------------

module GSL.Matrix(
    eigSg, eigHg,
    svdg,
    qr,
    chol,
    luSolveR, luSolveC,
    luR, luC,
    fromFile
) where

import Data.Packed.Internal
import Data.Packed.Matrix(fromLists,ident,takeDiag)
import GSL.Vector
import Foreign
import Foreign.C.Types
import Complex
import Foreign.C.String

{- | eigendecomposition of a real symmetric matrix using /gsl_eigen_symmv/.

> > let (l,v) = eigS $ 'fromLists' [[1,2],[2,1]]
> > l
> 3.000 -1.000
>
> > v
> 0.707 -0.707
> 0.707  0.707
>
> > v <> diag l <> trans v
> 1.000 2.000
> 2.000 1.000

-}
eigSg :: Matrix Double -> (Vector Double, Matrix Double)
eigSg (m@M {rows = r})
    | r == 1 = (fromList [cdat m `at` 0], singleton 1)
    | otherwise = unsafePerformIO $ do
        l <- createVector r
        v <- createMatrix RowMajor r r
        c_eigS // mat cdat m // vec l // mat dat v // check "eigSg" [cdat m]
        return (l,v)
foreign import ccall "gsl-aux.h eigensystemR" c_eigS :: TMVM

------------------------------------------------------------------



{- | eigendecomposition of a complex hermitian matrix using /gsl_eigen_hermv/

> > let (l,v) = eigH $ 'fromLists' [[1,2+i],[2-i,3]]
>
> > l
> 4.449 -0.449
>
> > v
>         -0.544          0.839
> (-0.751,0.375) (-0.487,0.243)
>
> > v <> diag l <> (conjTrans) v
>          1.000 (2.000,1.000)
> (2.000,-1.000)         3.000

-}
eigHg :: Matrix (Complex Double)-> (Vector Double, Matrix (Complex Double))
eigHg (m@M {rows = r})
    | r == 1 = (fromList [realPart $ cdat m `at` 0], singleton 1)
    | otherwise = unsafePerformIO $ do
        l <- createVector r
        v <- createMatrix RowMajor r r
        c_eigH // mat cdat m // vec l // mat dat v // check "eigHg" [cdat m]
        return (l,v)
foreign import ccall "gsl-aux.h eigensystemC" c_eigH :: TCMVCM


{- | Singular value decomposition of a real matrix, using /gsl_linalg_SV_decomp_mod/:

@\> let (u,s,v) = svdg $ 'fromLists' [[1,2,3],[-4,1,7]]
\
\> u
0.310 -0.951
0.951  0.310
\
\> s
8.497 2.792
\
\> v
-0.411 -0.785
 0.185 -0.570
 0.893 -0.243
\
\> u \<\> 'diag' s \<\> 'trans' v
 1. 2. 3.
-4. 1. 7.@

-}
svdg :: Matrix Double -> (Matrix Double, Vector Double, Matrix Double)
svdg x@M {rows = r, cols = c} = if r>=c
    then svd' x
    else (v, s, u) where (u,s,v) = svd' (trans x)

svd' x@M {rows = r, cols = c} = unsafePerformIO $ do
    u <- createMatrix RowMajor r c
    s <- createVector c
    v <- createMatrix RowMajor c c
    c_svd // mat cdat x // mat dat u // vec s // mat dat v // check "svdg" [cdat x]
    return (u,s,v)
foreign import ccall "gsl-aux.h svd" c_svd :: TMMVM

{- | QR decomposition of a real matrix using /gsl_linalg_QR_decomp/ and /gsl_linalg_QR_unpack/.

@\> let (q,r) = qr $ 'fromLists' [[1,3,5,7],[2,0,-2,4]]
\
\> q
-0.447 -0.894
-0.894  0.447
\
\> r
-2.236 -1.342 -0.447 -6.708
    0. -2.683 -5.367 -4.472
\
\> q \<\> r
1.000 3.000  5.000 7.000
2.000    0. -2.000 4.000@

-}
qr :: Matrix Double -> (Matrix Double, Matrix Double)
qr x@M {rows = r, cols = c} = unsafePerformIO $ do
    q <- createMatrix RowMajor r r
    rot <- createMatrix RowMajor r c
    c_qr // mat cdat x // mat dat q // mat dat rot // check "qr" [cdat x]
    return (q,rot)
foreign import ccall "gsl-aux.h QR" c_qr :: TMMM

{- | Cholesky decomposition of a symmetric positive definite real matrix using /gsl_linalg_cholesky_decomp/.

@\> let c = chol $ 'fromLists' [[5,4],[4,5]]
\
\> c
2.236    0.
1.789 1.342
\
\> c \<\> 'trans' c
5.000 4.000
4.000 5.000@

-}
chol :: Matrix Double -> Matrix Double
--chol x@(M r _ p) = createM [p] "chol" r r $ m c_chol x
chol x@M {rows = r} = unsafePerformIO $ do
    res <- createMatrix RowMajor r r
    c_chol // mat cdat x // mat dat res // check "chol" [cdat x]
    return res
foreign import ccall "gsl-aux.h chol" c_chol :: TMM

--------------------------------------------------------

{- -| efficient multiplication by the inverse of a matrix (for real matrices)
-}
luSolveR :: Matrix Double -> Matrix Double -> Matrix Double
luSolveR  a@(M {rows = n1, cols = n2}) b@(M {rows = r, cols = c})
    | n1==n2 && n1==r = unsafePerformIO $ do
        s <- createMatrix RowMajor r c
        c_luSolveR // mat cdat a // mat cdat b // mat dat s // check "luSolveR" [cdat a, cdat b]
        return s
    | otherwise = error "luSolveR of nonsquare matrix"

foreign import ccall "gsl-aux.h luSolveR" c_luSolveR ::  TMMM

{- -| efficient multiplication by the inverse of a matrix (for complex matrices). 
-}
luSolveC :: Matrix (Complex Double) -> Matrix (Complex Double) -> Matrix (Complex Double)
luSolveC  a@(M {rows = n1, cols = n2}) b@(M {rows = r, cols = c})
    | n1==n2 && n1==r = unsafePerformIO $ do
        s <- createMatrix RowMajor r c
        c_luSolveC // mat cdat a // mat cdat b // mat dat s // check "luSolveC" [cdat a, cdat b]
        return s
    | otherwise = error "luSolveC of nonsquare matrix"

foreign import ccall "gsl-aux.h luSolveC" c_luSolveC ::  TCMCMCM

{- | lu decomposition of real matrix (packed as a vector including l, u, the permutation and sign)
-}
luRaux  :: Matrix Double -> Vector Double
luRaux x@M {rows = r, cols = c} = unsafePerformIO $ do
    res <- createVector (r*r+r+1)
    c_luRaux // mat cdat x // vec res // check "luRaux" [cdat x]
    return res
foreign import ccall "gsl-aux.h luRaux" c_luRaux :: TMV

{- | lu decomposition of complex matrix (packed as a vector including l, u, the permutation and sign)
-}
luCaux  :: Matrix (Complex Double) -> Vector (Complex Double)
luCaux x@M {rows = r, cols = c} = unsafePerformIO $ do
    res <- createVector (r*r+r+1)
    c_luCaux // mat cdat x // vec res // check "luCaux" [cdat x]
    return res
foreign import ccall "gsl-aux.h luCaux" c_luCaux :: TCMCV

{- | The LU decomposition of a square matrix. Is based on /gsl_linalg_LU_decomp/ and  /gsl_linalg_complex_LU_decomp/ as described in <http://www.gnu.org/software/gsl/manual/gsl-ref_13.html#SEC223>.

@\> let m = 'fromLists' [[1,2,-3],[2+3*i,-7,0],[1,-i,2*i]]
\> let (l,u,p,s) = luR m@

L is the lower triangular:

@\> l
          1.            0.  0.
0.154-0.231i            1.  0.
0.154-0.231i  0.624-0.522i  1.@

U is the upper triangular:

@\> u
2.+3.i           -7.            0.
    0.  3.077-1.615i           -3.
    0.            0.  1.873+0.433i@

p is a permutation:

@\> p
[1,0,2]@

L \* U obtains a permuted version of the original matrix:

@\> 'extractRows' p m
  2.+3.i   -7.   0.
      1.    2.  -3.
      1.  -1.i  2.i
\ 
\> l \<\> u
 2.+3.i   -7.   0.
     1.    2.  -3.
     1.  -1.i  2.i@

s is the sign of the permutation, required to obtain sign of the determinant:

@\> s * product ('toList' $ 'takeDiag' u)
(-18.0) :+ (-16.000000000000004)
\> 'LinearAlgebra.Algorithms.det' m
(-18.0) :+ (-16.000000000000004)@

 -}
luR :: Matrix Double -> (Matrix Double, Matrix Double, [Int], Double)
luR m = (l,u,p, fromIntegral s') where
    r = rows m
    v = luRaux m
    lu = reshape r $ subVector 0 (r*r) v
    s':p = map round . toList . subVector (r*r) (r+1) $ v
    u = triang r r 0 1`mul` lu
    l = (triang r r 0 0 `mul` lu) `add` ident r
    add = liftMatrix2 $ vectorZipR Add
    mul = liftMatrix2 $ vectorZipR Mul

-- | Complex version of 'luR'.
luC :: Matrix (Complex Double) -> (Matrix (Complex Double), Matrix (Complex Double), [Int], Complex Double)
luC m = (l,u,p, fromIntegral s') where
    r = rows m
    v = luCaux m
    lu = reshape r $ subVector 0 (r*r) v
    s':p = map (round.realPart) . toList . subVector (r*r) (r+1) $ v
    u = triang r r 0 1 `mul` lu
    l = (triang r r 0 0 `mul` lu) `add` ident r
    add = liftMatrix2 $ vectorZipC Add
    mul = liftMatrix2 $ vectorZipC Mul

extract l is = [l!!i |i<-is]

{- auxiliary function to get triangular matrices
-}
triang r c h v = reshape c $ fromList [el i j | i<-[0..r-1], j<-[0..c-1]]
    where el i j = if j-i>=h then v else 1 - v

{- | rearranges the rows of a matrix according to the order given in a list of integers. 

> > extractRows [3,3,0,1] (ident 4)
> 0. 0. 0. 1.
> 0. 0. 0. 1.
> 1. 0. 0. 0.
> 0. 1. 0. 0.

-}
extractRows :: Field t => [Int] -> Matrix t -> Matrix t
extractRows l m = fromRows $ extract (toRows $ m) l

--------------------------------------------------------------

-- | loads a matrix efficiently from formatted ASCII text file (the number of rows and columns must be known in advance).
fromFile :: FilePath -> (Int,Int) -> IO (Matrix Double)
fromFile filename (r,c) = do
    charname <- newCString filename
    res <- createMatrix RowMajor r c
    c_gslReadMatrix charname // mat dat res // check "gslReadMatrix" []
    --free charname  -- TO DO: free the auxiliary CString
    return res
foreign import ccall "gsl-aux.h matrix_fscanf" c_gslReadMatrix:: Ptr CChar -> TM

---------------------------------------------------------------------------