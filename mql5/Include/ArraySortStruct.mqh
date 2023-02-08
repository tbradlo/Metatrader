template <typename T>
void ArrayReindex( T &Array[], const double &TmpSort[][2] )
{
  T TmpArray[];

  for (int x = ::ArrayResize(TmpArray, ::ArrayRange(TmpSort, 0)) - 1; x >= 0; x--)
    TmpArray[x] = Array[(int)(TmpSort[x][1] + 0.1)];

  ::ArraySwap(Array, TmpArray);

  return;
}

// Сортировка массива структур и указателей на объекты по (под-) полю/методу.
#define  ArraySortStruct(ARRAY, FIELD)                                      \
{                                                                          \
  double TmpSort[][2];                                                     \
                                                                           \
  for (int x =::ArrayResize(TmpSort, ::ArraySize(ARRAY)) - 1; x >= 0; x--) \
  {                                                                        \
    TmpSort[x][0] = (double)ARRAY[x].FIELD;                                \
    TmpSort[x][1] = x;                                                     \
  }                                                                        \
                                                                           \
  ::ArraySort(TmpSort);                                                    \
  ::ArrayReindex(ARRAY, TmpSort);                                          \
}