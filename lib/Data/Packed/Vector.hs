-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Packed.Vector
-- Copyright   :  (c) Alberto Ruiz 2007
-- License     :  GPL-style
--
-- Maintainer  :  Alberto Ruiz <aruiz@um.es>
-- Stability   :  provisional
-- Portability :  portable
--
-- 1D arrays suitable for numeric computations using external libraries.
--
-----------------------------------------------------------------------------

module Data.Packed.Vector (
    Vector,
    fromList, (|>), toList, buildVector,
    dim, (@>),
    subVector, takesV, join,
    constant, linspace,
    vecdisp,
--    moved to Numeric.LinearAlgebra.Interface typeclass
--    vectorFMax, vectorFMin, vectorFMaxIndex, vectorFMinIndex,
--    vectorMax, vectorMin,
    vectorMaxIndex, vectorMinIndex,
    mapVector, zipVector,
    fscanfVector, fprintfVector, freadVector, fwriteVector,
    foldLoop, foldVector, foldVectorG
) where

import Data.Packed.Internal
import Numeric.GSL.Vector
-- import Data.Packed.ST


import Data.Binary
import Foreign.Storable
import Control.Monad(replicateM)

-------------------------------------------------------------------

-- a 64K cache, with a Double taking 13 bytes in Bytestring,
-- implies a chunk size of 5041
chunk :: Int
chunk = 5000

chunks :: Int -> [Int]
chunks d = let c = d `div` chunk
               m = d `mod` chunk
           in if m /= 0 then reverse (m:(replicate c chunk)) else (replicate c chunk)  

putVector v = do
              let d = dim v
              mapM_ (\i -> put $ v @> i) [0..(d-1)]

getVector d = do
              xs <- replicateM d get
              return $! fromList xs

instance (Binary a, Storable a) => Binary (Vector a) where
    put v = do
            let d = dim v
            put d
            mapM_ putVector $! takesV (chunks d) v
    get = do
          d <- get
          vs <- mapM getVector $ chunks d
          return $! join vs

-------------------------------------------------------------------


{- | Creates a real vector containing a range of values:

@\> linspace 5 (-3,7)
5 |> [-3.0,-0.5,2.0,4.5,7.0]@

Logarithmic spacing can be defined as follows:

@logspace n (a,b) = 10 ** linspace n (a,b)@
-}
linspace :: Int -> (Double, Double) -> Vector Double
linspace n (a,b) = add a $ scale s  $ fromList [0 .. fromIntegral n-1]
    where scale = vectorMapValR Scale
          add   = vectorMapValR AddConstant
          s = (b-a)/fromIntegral (n-1)

{-
vectorFMax :: Vector Float -> Float
vectorFMax = toScalarF Max

vectorFMin :: Vector Float -> Float
vectorFMin = toScalarF Min

vectorFMaxIndex :: Vector Float -> Int
vectorFMaxIndex = round . toScalarF MaxIdx

vectorFMinIndex :: Vector Float -> Int
vectorFMinIndex = round . toScalarF MinIdx

vectorMax :: Vector Double -> Double
vectorMax = toScalarR Max

vectorMin :: Vector Double -> Double
vectorMin = toScalarR Min
-}

{-# DEPRECATED vectorMaxIndex "use minIdx" #-}
vectorMaxIndex :: Vector Double -> Int
vectorMaxIndex = round . toScalarR MaxIdx

{-# DEPRECATED vectorMinIndex "use maxIdx" #-}
vectorMinIndex :: Vector Double -> Int
vectorMinIndex = round . toScalarR MinIdx


{- | creates a vector with a given number of equal components:

@> constant 2 7
7 |> [2.0,2.0,2.0,2.0,2.0,2.0,2.0]@
-}
constant :: Element a => a -> Int -> Vector a
-- constant x n = runSTVector (newVector x n)
constant = constantD -- about 2x faster

{- | creates a Vector of the specified length using the supplied function to
     to map the index to the value at that index.

@> buildVector 4 fromIntegral
4 |> [0.0,1.0,2.0,3.0]@

-}
buildVector :: Element a => Int -> (Int -> a) -> Vector a
buildVector len f =
    fromList $ map f [0 .. (len - 1)]


{- | Show a vector using a function for showing matrices.

@disp = putStr . vecdisp ('dispf' 2)

\> disp ('linspace' 10 (0,1))
10 |> 0.00  0.11  0.22  0.33  0.44  0.56  0.67  0.78  0.89  1.00
@
-}
vecdisp :: (Element t) => (Matrix t -> String) -> Vector t -> String
vecdisp f v
    = ((show (dim v) ++ " |> ") ++) . (++"\n")
    . unwords . lines .  tail . dropWhile (not . (`elem` " \n"))
    . f . trans . reshape 1
    $ v
