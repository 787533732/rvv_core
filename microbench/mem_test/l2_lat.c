#include <stdio.h>
int main()
{
  double second();
  double time;
  int* a[131072];
  int **b;
  long int c;
  long i,j,k,l,secx;
  /* Load L2 cache */
  for (i=0;i<131071;i++){
    a[i]=(int *)&a[i+1];
  }
  time=second();
  /* loop 1500 times */
  for (i=0;i<250;i++) {
    b = (int **)a[7];
    /* Load from L2 at 64 byte boundary */
    for(k=0;k<80000;k+=8) {
	b = (int **) b[8];
    }
  }
  time=second()-time;
  fprintf(stderr, "Time is %g\n",time);
  fprintf(stderr, "L2 Latency is %g\n",(463000000*time)/(20001*250));
  fprintf(stderr, "L2 BW is %f MB/sec\n",(20001*250*64)/(time*1000000));
  fprintf(stderr, "b is %ld\n",b);
}
