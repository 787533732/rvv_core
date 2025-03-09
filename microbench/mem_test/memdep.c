#include <stdio.h>
int main()
{
  int* a[2048];
  int **b;
  long int c;
  long i,j,k,l,secx;
  /* Load L2 cache */
  for (i=0;i<2047;i++){
    a[i]=(int *)&a[i+1];
  }
  /* loop 15000 times */
  for (i=0;i<15000;i++) {
      b = (int **)a[0];
    /* Load from L2 at 64 byte boundary */
    for(k=1;k<1000;k++) {
	b = (int **) b[1];
	
    }
  }
  fprintf(stderr, "b is %ld\n",b);
}
