#property strict

// Сортировка массива структур и указателей на объекты по (под-) полю/методу.
#define ArraySortStruct(ARRAY, FIELD)                                            \
{                                                                                \
  class SORT                                                                     \
  {                                                                              \
  private:                                                                       \
    template <typename T>                                                        \
    static void Swap( T &Array[], const int i, const int j )                     \
    {                                                                            \
      const T Temp = Array[i];                                                   \
                                                                                 \
      Array[i] = Array[j];                                                       \
      Array[j] = Temp;                                                           \
                                                                                 \
      return;                                                                    \
    }                                                                            \
                                                                                 \
    template <typename T>                                                        \
    static int Partition( T &Array[], const int Start, const int End )           \
    {                                                                            \
      int Marker = Start;                                                        \
                                                                                 \          
      for (int i = Start; i <= End; i++)                                         \
        if (Array[i].##FIELD <= Array[End].##FIELD)                              \
        {                                                                        \
          SORT::Swap(Array, i, Marker);                                          \
                                                                                 \
          Marker++;                                                              \
        }                                                                        \
                                                                                 \
       return(Marker - 1);                                                       \
    }                                                                            \
                                                                                 \
    template <typename T>                                                        \
    static void QuickSort( T &Array[], const int Start, const int End )          \
    {                                                                            \
      if (Start < End)                                                           \
      {                                                                          \
        const int Pivot = Partition(Array, Start, End);                          \
                                                                                 \
        SORT::QuickSort(Array, Start, Pivot - 1);                                \
        SORT::QuickSort(Array, Pivot + 1, End);                                  \
      }                                                                          \
                                                                                 \
      return;                                                                    \
    }                                                                            \
                                                                                 \
  public:                                                                        \
    template <typename T>                                                        \ 
    static void Sort( T &Array[], int Count = WHOLE_ARRAY, const int Start = 0 ) \
    {                                                                            \
      if (Count == WHOLE_ARRAY)                                                  \
        Count = ::ArraySize(Array);                                              \
                                                                                 \
      SORT::QuickSort(Array, Start, Start + Count - 1);                          \
                                                                                 \
      return;                                                                    \
    }                                                                            \
  };                                                                             \
                                                                                 \
  SORT::Sort(ARRAY);                                                             \
}