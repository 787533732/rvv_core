#include "stdio.h"
/* dependent loads */
void main() {
  float a[8192], j=1.1;
  int i, k=2, l=3, m=4, n=5, o=6, p=7,r;
  for (i=0;i<8192;i++) {
    a[i] = i+0.1;
  }
  for (r=0;r<500;r++) {
    for (i=0;i<8191;i++) {
      j=a[i]+j;
    }
  }
  printf("j k l m n o p %f %d %d %d %d %d %d\n",j,k,l,m,n,o,p);
}

