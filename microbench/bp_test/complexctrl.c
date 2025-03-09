#include <stdio.h>
void main() {
  int i=0, j=-1, k=2, l=3, m=-1, n=5,o=6;
  for (i=0;i<1000;i++) {
    if (i%2 == 0) {
      j++;
      j%=4;
      switch (j) {
	case 0:
	case 1:
	  k++;
	  break;
	case 2:
	case 3:
	  l++;
      }
    }
    else {
      m++;
      m%=6;
      switch (m) {
	case 0:
	case 1:
	case 2:
	  n++;
	  break;
	case 3:
	case 4:
	case 5:
	  o++;
      }
    }
  }
  //printf("k,l,n,o %d %d %d %d\n",k,l,n,o);
}
