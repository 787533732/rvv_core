#include <stdio.h>
int main()
{
  double second();
  double time;
  int* a[524288];
  int **b;
  long i,j,k,l,secx;
  /* Load L2 cache */
  for (i=0;i<524287;i++){
    a[i]=(int *)&a[i+1];
  }
  time=second();
  /* loop 750 times */
  for (i=0;i<75;i++) {
    b = (int **)a[0];
    /* Load from memory at 64 byte boundary */
    for(k=0;k<160000;k+=8) {
	b = (int **) b[8];
    }
    b = (int **)a[262144];
    for (k=0;k<160000;k+=8)
      b = (int **)b[8];
  }
  time=second()-time;
  /* time taken is time for (26216/8 + 1)*2*750 loads from main memory */
  fprintf(stderr, "Time is %g\n",time);
  fprintf(stderr, "Memory latency is %g\n",(463000000*time)/(20001*2*75));
  fprintf(stderr, "Memory BW is %f MB/sec\n", (20001*2*75*64)/(time*1000000));
  fprintf(stderr, "b is %ld\n",b);
}
