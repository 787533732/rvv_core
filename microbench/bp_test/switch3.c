#include <stdio.h>
void main() {
  int i,j, k=1, l=2, m=3, n=4, o=5;
  for (i=0;i<4000000;i++) {
    j=i%30;
    switch (j) {
      case 0:
      case 1:
      case 2:
	k++;
	break;
      case 3:
      case 4:
      case 5:
	l++;
	break;
      case 6:
      case 7:
      case 8:
	m++;
	break;
      case 9:
      case 10:
      case 11:
	n++;
	break;
      case 12:
      case 13:
      case 14:
	o++;
	break;
      case 15:
      case 16:
      case 17:
	k--;
	break;
      case 18:
      case 19:
      case 20:
        l--;
	break;
      case 21:
      case 22:
      case 23:
	m--;
	break;
      case 24:
      case 25:
      case 26:
	n--;
	break;
      case 27:
      case 28:
      case 29:
	o--;
    }
  }
  printf("k l m n o %d %d %d %d %d\n",k,l,m,n,o);
}
