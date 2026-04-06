export function buildLineChartConfig(labels, values, label = 'Series') {
  return {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label,
          data: values,
          borderColor: '#00A651',
          backgroundColor: 'rgba(0, 166, 81, 0.14)',
          tension: 0.3,
          fill: true,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
    },
  };
}
