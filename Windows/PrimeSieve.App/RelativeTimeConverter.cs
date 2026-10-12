using System.Globalization;
using System.Windows;
using System.Windows.Data;
namespace PrimeSieve.App;
public sealed class RelativeTimeConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture) =>
        values is [double value, double baseline] && baseline > 0 ? (value / baseline).ToString("F2", culture) + "×" : "—";
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        targetTypes.Select(_ => DependencyProperty.UnsetValue).ToArray();
}
